#!/usr/bin/env python3
"""Rewrite a repo manifest to reflect the current branches in a repo checkout."""

from __future__ import annotations

import argparse
import difflib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable
from xml.sax.saxutils import quoteattr


WARNINGS_EMITTED = False


@dataclass(frozen=True)
class Project:
    name: str
    path: str
    revision: str | None = None


@dataclass(frozen=True)
class ProjectState:
    branch: str | None
    clean: bool


class ToolError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Read a repo manifest and emit extend-project entries whose revision "
            "matches each project's current local branch."
        )
    )
    parser.add_argument("manifest", help="Input manifest XML file")
    parser.add_argument(
        "--remote",
        metavar="REMOTE",
        help=(
            "Warn if the current local branch is not present on the given git "
            "remote for a project"
        ),
    )
    parser.add_argument(
        "--verify-pushed",
        action="store_true",
        help=(
            "When used with --remote, warn unless the remote branch tip exactly "
            "matches the local HEAD commit"
        ),
    )
    parser.add_argument(
        "--diff",
        action="store_true",
        help="Output only changed lines, prefixed with - and + for old and new content",
    )
    return parser.parse_args()


def warn(message: str) -> None:
    global WARNINGS_EMITTED
    WARNINGS_EMITTED = True
    print(f"warning: {message}", file=sys.stderr)


def run_git(repo_path: Path, args: Iterable[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(repo_path), *args],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def find_workspace_root(manifest_path: Path) -> Path:
    candidates = [Path.cwd(), manifest_path.resolve().parent]
    seen: set[Path] = set()

    for candidate in candidates:
        current = candidate
        while True:
            if current in seen:
                break
            seen.add(current)
            if (current / ".repo" / "manifests").is_dir():
                return current
            if current.parent == current:
                break
            current = current.parent

    raise ToolError(
        f"unable to locate workspace root for manifest {manifest_path}; "
        "run from a repo checkout or place the manifest under that checkout"
    )


def load_projects(manifest_path: Path) -> list[Project]:
    projects: list[Project] = []
    visited: set[Path] = set()

    def visit(path: Path) -> None:
        resolved = path.resolve()
        if resolved in visited:
            return
        visited.add(resolved)

        try:
            root = ET.parse(resolved).getroot()
        except ET.ParseError as exc:
            raise ToolError(f"failed to parse {resolved}: {exc}") from exc

        default = root.find("default")
        default_revision = None if default is None else default.get("revision")

        for child in root:
            if child.tag == "include":
                include_name = child.get("name")
                if not include_name:
                    raise ToolError(f"include without name in {resolved}")
                include_path = resolved.parent / include_name
                if not include_path.is_file():
                    raise ToolError(f"included manifest not found: {include_path}")
                visit(include_path)
            elif child.tag == "project":
                name = child.get("name")
                if not name:
                    raise ToolError(f"project without name in {resolved}")
                project_path = child.get("path") or name
                revision = child.get("revision") or default_revision
                projects.append(Project(name=name, path=project_path, revision=revision))
            elif child.tag == "extend-project":
                name = child.get("name")
                revision = child.get("revision")
                if not name or revision is None:
                    continue
                extend_path = child.get("path")
                for index, project in enumerate(projects):
                    if project.name != name:
                        continue
                    if extend_path is not None and project.path != extend_path:
                        continue
                    projects[index] = Project(
                        name=project.name,
                        path=project.path,
                        revision=revision,
                    )

    visit(manifest_path)
    return projects


def unique_projects(projects: list[Project]) -> list[Project]:
    seen: set[tuple[str, str]] = set()
    unique: list[Project] = []
    for project in projects:
        key = (project.name, project.path)
        if key in seen:
            continue
        seen.add(key)
        unique.append(project)
    return unique


def project_key(project: Project) -> tuple[str, str]:
    return (project.name, project.path)


def git_stdout(repo_path: Path, args: Iterable[str]) -> str | None:
    proc = run_git(repo_path, args)
    if proc.returncode != 0:
        return None
    return proc.stdout.strip()


def resolve_revision_commit(repo_path: Path, revision: str) -> str | None:
    direct = git_stdout(repo_path, ["rev-parse", "--verify", f"{revision}^{{commit}}"])
    if direct:
        return direct

    branch = revision.removeprefix("refs/heads/")
    remotes = git_stdout(repo_path, ["remote"])
    if not remotes:
        return None

    for remote in remotes.splitlines():
        candidate = git_stdout(repo_path, ["rev-parse", "--verify", f"{remote}/{branch}^{{commit}}"])
        if candidate:
            return candidate
    return None


def branch_from_manifest(repo_path: Path, project: Project) -> str | None:
    if not project.revision:
        return None

    head = git_stdout(repo_path, ["rev-parse", "HEAD"])
    if not head:
        return None

    revision_commit = resolve_revision_commit(repo_path, project.revision)
    if revision_commit != head:
        return None

    return project.revision


def project_branch(repo_path: Path, project: Project) -> ProjectState:
    status = run_git(repo_path, ["status", "--porcelain"])
    clean = False
    if status.returncode != 0:
        warn(f"{project.path}: git status failed: {status.stderr.strip() or 'unknown error'}")
    elif status.stdout.strip():
        warn(f"{project.path}: repository is not clean")
    else:
        clean = True

    branch = run_git(repo_path, ["symbolic-ref", "--quiet", "--short", "HEAD"])
    if branch.returncode != 0:
        manifest_branch = branch_from_manifest(repo_path, project)
        if manifest_branch:
            return ProjectState(branch=manifest_branch, clean=clean)

        detail = branch.stderr.strip() or "detached HEAD"
        warn(f"{project.path}: unable to determine current branch ({detail})")
        return ProjectState(branch=None, clean=clean)

    return ProjectState(branch=branch.stdout.strip(), clean=clean)


def ensure_remote_configured(repo_path: Path, project: Project, remote: str) -> bool:
    remote_check = run_git(repo_path, ["remote", "get-url", remote])
    if remote_check.returncode == 0:
        return True
    warn(f"{project.path}: git remote {remote!r} is not configured")
    return False


def remote_branch_sha(repo_path: Path, remote: str, branch: str) -> str | None:
    head_ref = branch.removeprefix("refs/heads/")
    check = run_git(repo_path, ["ls-remote", "--exit-code", "--heads", remote, head_ref])
    if check.returncode != 0:
        return None
    return check.stdout.split()[0]


def verify_remote_branch(repo_path: Path, project: Project, remote: str, branch: str) -> None:
    if not ensure_remote_configured(repo_path, project, remote):
        return

    if remote_branch_sha(repo_path, remote, branch) is not None:
        return
    warn(f"{project.path}: branch {branch!r} is not present on remote {remote!r}")


def verify_remote_branch_tip(repo_path: Path, project: Project, remote: str, branch: str) -> None:
    if not ensure_remote_configured(repo_path, project, remote):
        return

    head_ref = branch.removeprefix("refs/heads/")
    remote_sha = remote_branch_sha(repo_path, remote, branch)
    if remote_sha is None:
        warn(f"{project.path}: branch {branch!r} is not present on remote {remote!r}")
        return

    local_sha = git_stdout(repo_path, ["rev-parse", "HEAD"])
    if not local_sha:
        warn(f"{project.path}: unable to resolve local HEAD commit")
        return

    if remote_sha != local_sha:
        warn(
            f"{project.path}: remote {remote!r} branch {head_ref!r} is at {remote_sha}, "
            f"local HEAD is {local_sha}"
        )


def format_extend_project(project: Project, branch: str, *, include_path: bool) -> str:
    attrs = [f'name={quoteattr(project.name)}']
    if include_path:
        attrs.append(f'path={quoteattr(project.path)}')
    attrs.append(f'revision={quoteattr(branch)}')
    return f"<extend-project {' '.join(attrs)}/>"


def replace_revision_attribute(tag_text: str, revision: str) -> str:
    replacement = quoteattr(revision)
    revision_pattern = re.compile(r'(\brevision\s*=\s*)(["\']).*?\2', re.DOTALL)
    if revision_pattern.search(tag_text):
        return revision_pattern.sub(lambda match: f"{match.group(1)}{replacement}", tag_text, count=1)

    stripped = tag_text.rstrip()
    trailer = tag_text[len(stripped):]
    if stripped.endswith("/>"):
        return f"{stripped[:-2]} revision={replacement}/>{trailer}"
    if stripped.endswith(">"):
        return f"{stripped[:-1]} revision={replacement}>{trailer}"
    return tag_text


def rewrite_top_level_manifest(
    manifest_path: Path,
    resolved_branches: dict[tuple[str, str], str],
    projects: list[Project],
    name_counts: dict[str, int],
) -> str:
    original = manifest_path.read_text()
    top_level_root = ET.parse(manifest_path).getroot()

    top_level_keys: set[tuple[str, str]] = set()
    top_level_name_keys: set[str] = set()
    for child in top_level_root:
        if child.tag not in {"project", "extend-project"}:
            continue
        name = child.get("name")
        if not name:
            continue
        path = child.get("path")
        if child.tag == "project":
            key = (name, path or name)
            top_level_keys.add(key)
        else:
            if path is None:
                top_level_name_keys.add(name)
            else:
                top_level_keys.add((name, path))

    tag_pattern = re.compile(r"<(project|extend-project)\b[^<>]*?>", re.DOTALL)

    def replace_tag(match: re.Match[str]) -> str:
        tag_text = match.group(0)
        name_match = re.search(r'\bname\s*=\s*(["\'])(.*?)\1', tag_text, re.DOTALL)
        if not name_match:
            return tag_text
        name = name_match.group(2)
        path_match = re.search(r'\bpath\s*=\s*(["\'])(.*?)\1', tag_text, re.DOTALL)
        path = path_match.group(2) if path_match else None

        if match.group(1) == "project":
            key = (name, path or name)
            branch = resolved_branches.get(key)
        elif path is not None:
            branch = resolved_branches.get((name, path))
        else:
            branch = None
            matches = [resolved_branches[project_key(project)] for project in projects if project.name == name and project_key(project) in resolved_branches]
            if matches:
                if len(set(matches)) == 1:
                    branch = matches[0]
                else:
                    warn(f"{name}: multiple branch values prevent safe rewrite of top-level extend-project without path")

        if not branch:
            return tag_text
        return replace_revision_attribute(tag_text, branch)

    rewritten = tag_pattern.sub(replace_tag, original)

    extra_lines: list[str] = []
    for project in projects:
        key = project_key(project)
        branch = resolved_branches.get(key)
        if not branch:
            continue
        if branch == project.revision:
            continue
        if key in top_level_keys or project.name in top_level_name_keys:
            continue
        extra_lines.append(
            "  " + format_extend_project(project, branch, include_path=name_counts[project.name] > 1)
        )

    if not extra_lines:
        return rewritten

    block = "\n".join(
        [
            "",
            "  <!-- Local branch overrides for included manifests -->",
            *extra_lines,
        ]
    )

    closing = "</manifest>"
    idx = rewritten.rfind(closing)
    if idx == -1:
        raise ToolError(f"closing </manifest> not found in {manifest_path}")
    return rewritten[:idx] + block + "\n" + rewritten[idx:]


def render_diff(original: str, rewritten: str) -> str:
    lines: list[str] = []
    for line in difflib.ndiff(original.splitlines(), rewritten.splitlines()):
        if line.startswith("- "):
            lines.append("-" + line[2:])
        elif line.startswith("+ "):
            lines.append("+" + line[2:])
    return "\n".join(lines) + ("\n" if lines else "")


def main() -> int:
    args = parse_args()
    if args.verify_pushed and not args.remote:
        raise ToolError("--verify-pushed requires --remote")

    manifest_path = Path(args.manifest).expanduser().resolve()
    if not manifest_path.is_file():
        raise ToolError(f"manifest not found: {manifest_path}")

    workspace_root = find_workspace_root(manifest_path)
    projects = unique_projects(load_projects(manifest_path))
    name_counts: dict[str, int] = {}
    for project in projects:
        name_counts[project.name] = name_counts.get(project.name, 0) + 1
    resolved_branches: dict[tuple[str, str], str] = {}

    for project in projects:
        repo_path = workspace_root / project.path
        if not repo_path.exists():
            warn(f"{project.path}: path does not exist under {workspace_root}")
            continue
        if not (repo_path / ".git").exists():
            warn(f"{project.path}: not a git repository")
            continue

        state = project_branch(repo_path, project)
        branch = state.branch
        if not branch:
            continue

        if args.remote:
            manifest_unchanged = project.revision == branch
            if not (state.clean and manifest_unchanged):
                if args.verify_pushed:
                    verify_remote_branch_tip(repo_path, project, args.remote, branch)
                else:
                    verify_remote_branch(repo_path, project, args.remote, branch)

        resolved_branches[project_key(project)] = branch

    original_text = manifest_path.read_text()
    rewritten_text = rewrite_top_level_manifest(
        manifest_path,
        resolved_branches,
        projects,
        name_counts,
    )
    if args.diff:
        sys.stdout.write(render_diff(original_text, rewritten_text))
    else:
        sys.stdout.write(rewritten_text)

    return 1 if WARNINGS_EMITTED else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ToolError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(2)

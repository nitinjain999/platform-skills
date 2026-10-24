#!/usr/bin/env bash
# Exercise bundled audit scripts offline, from a different repository.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 - "${1:-.}" <<'PY'
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

bundle = Path(sys.argv[1]).resolve()
audit_dir = bundle / "examples/fluxcd/repo-audit"
bash = shutil.which("bash")
native_kubectl = shutil.which("kubectl")
stub = r'''
import json, os, sys
from pathlib import Path
name, args = Path(sys.argv[0]).name, sys.argv[1:]
with open(os.environ["AUDIT_TEST_LOG"], "a") as log:
    log.write(json.dumps({"tool": name, "args": args, "cwd": os.getcwd()}) + "\n")
if name == "flux":
    if args[:1] == ["version"]:
        print("flux: v2.9.6")
    elif args[:1] == ["schema"]:
        sys.exit(1)
    elif args[:1] == ["migrate"]:
        print(os.environ.get("AUDIT_TEST_FLUX_OUTPUT", ""))
        if os.environ.get("AUDIT_TEST_LARGE_REPORT"):
            print("unchanged resource\n" * 100000)
        sys.exit(int(os.environ.get("AUDIT_TEST_FLUX_EXIT", "0")))
    else:
        sys.exit(2)
elif name == "flux-schema":
    if args[:1] == ["version"]:
        print("flux-schema version " + os.environ.get("AUDIT_TEST_SCHEMA_VERSION", "0.10.0"))
    elif args[:1] == ["discover"]:
        print(json.dumps({"inventory": "fixture"}))
    elif args[:1] == ["validate"]:
        print("Summary: Valid: 1, Invalid: 0, Skipped: 0")
        sys.exit(int(os.environ.get("AUDIT_TEST_SCHEMA_EXIT", "0")))
    else:
        sys.exit(2)
elif name == "kubectl":
    if args[:1] != ["kustomize"]:
        sys.exit(2)
    if os.environ.get("AUDIT_TEST_NATIVE_KUBECTL"):
        os.execv(os.environ["AUDIT_TEST_NATIVE_KUBECTL"], ["kubectl", *args])
    print("apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: rendered")
    sys.exit(int(os.environ.get("AUDIT_TEST_BUILD_EXIT", "0")))
elif name == "helm":
    if args[:1] != ["template"]:
        sys.exit(2)
    print("apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: chart")
else:
    sys.exit(99)  # No git/curl/wget execution is permitted in an audit.
'''


class AuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="flux-audit-")
        self.addCleanup(self.temp.cleanup)
        self.repo = (Path(self.temp.name) / "unrelated repository with spaces").resolve()
        self.repo.mkdir()
        self.bin = Path(self.temp.name) / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.defpath,
                        AUDIT_TEST_LOG=str(Path(self.temp.name) / "calls.jsonl"))
        for name in ("flux", "flux-schema", "kubectl", "helm", "git", "curl", "wget"):
            command = self.bin / name
            command.write_text("#!" + sys.executable + "\n" + stub)
            command.chmod(0o755)
        (self.repo / "resource.yaml").write_text(
            "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: fixture\n"
        )

    def run_helper(self, name, *args):
        return subprocess.run([bash, str(audit_dir / "scripts" / name), *args],
                              cwd=self.repo, env=self.env, text=True, capture_output=True)

    def calls(self):
        return [json.loads(line) for line in
                Path(self.env["AUDIT_TEST_LOG"]).read_text().splitlines()]

    def test_discovery_preserves_target_and_exclusions(self):
        result = self.run_helper("discover.sh", "-d", str(self.repo), "-e", "terraform")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"inventory": "fixture"})
        self.assertEqual(self.calls()[-1]["args"],
                         ["discover", str(self.repo), "-o", "json", "--skip-file", "terraform"])

    def test_discovery_rejects_old_schema_cli(self):
        self.env["AUDIT_TEST_SCHEMA_VERSION"] = "0.9.9"
        result = self.run_helper("discover.sh", "-d", str(self.repo))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("too old", result.stderr)

    def test_missing_dependencies_fail(self):
        empty = Path(self.temp.name) / "empty"
        empty.mkdir()
        self.env["PATH"] = str(empty)
        for script in ("discover.sh", "validate.sh", "check-deprecated.sh"):
            with self.subTest(script=script):
                self.assertNotEqual(self.run_helper(script, "-d", ".").returncode, 0)

    def test_deprecation_check_is_a_dry_run(self):
        result = self.run_helper("check-deprecated.sh", "-d", str(self.repo))
        self.assertEqual(result.returncode, 0, result.stderr)
        call = self.calls()[-1]
        self.assertEqual(call["args"], ["migrate", "-f", ".", "--dry-run"])
        self.assertEqual(call["cwd"], str(self.repo.resolve()))

    def test_deprecated_versions_fail(self):
        self.env["AUDIT_TEST_FLUX_OUTPUT"] = "file.yaml:11: HelmRelease v2beta2 -> v2"
        for status in ("0", "1"):
            self.env["AUDIT_TEST_FLUX_EXIT"] = status
            self.assertEqual(self.run_helper("check-deprecated.sh", "-d", ".").returncode, 1)

    def test_large_deprecation_report_cannot_report_a_clean_audit(self):
        self.env["AUDIT_TEST_FLUX_OUTPUT"] = "file.yaml:11: HelmRelease v2beta2 -> v2"
        self.env["AUDIT_TEST_LARGE_REPORT"] = "1"
        result = self.run_helper("check-deprecated.sh", "-d", ".")
        self.assertEqual(result.returncode, 1)
        self.assertIn("deprecated Flux API versions found", result.stderr)
        self.assertNotIn("No deprecated", result.stdout)

    def test_migration_errors_cannot_report_a_clean_audit(self):
        self.env["AUDIT_TEST_FLUX_EXIT"] = "42"
        self.env["AUDIT_TEST_FLUX_OUTPUT"] = "unable to read manifest"
        result = self.run_helper("check-deprecated.sh", "-d", ".")
        self.assertEqual(result.returncode, 42)
        self.assertNotIn("No deprecated", result.stdout)

    def test_validation_handles_manifests_and_overlays(self):
        overlay = self.repo / "an overlay"
        overlay.mkdir()
        (overlay / "kustomization.yaml").write_text("resources: []\n")
        result = self.run_helper("validate.sh", "-d", str(self.repo))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        builds = [call for call in calls if call["tool"] == "kubectl"]
        self.assertEqual(len(builds), 1)
        self.assertEqual(builds[0]["args"], ["kustomize", str(overlay)])
        self.assertEqual(len([call for call in calls
                              if call["tool"] == "flux-schema" and
                              call["args"][:1] == ["validate"]]), 2)

    def test_all_kustomization_filenames_are_built_and_excluded_from_standalone(self):
        overlays = []
        for filename in ("kustomization.yaml", "kustomization.yml", "Kustomization"):
            overlay = self.repo / (filename + " overlay")
            overlay.mkdir()
            (overlay / filename).write_text("resources: []\n")
            (overlay / "resource.yaml").write_text("kind: ConfigMap\n")
            overlays.append(str(overlay))
        result = self.run_helper("validate.sh", "-d", str(self.repo))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        self.assertCountEqual([call["args"][1] for call in calls
                               if call["tool"] == "kubectl"], overlays)
        validations = [call for call in calls if call["tool"] == "flux-schema"
                       and call["args"][:1] == ["validate"]]
        self.assertEqual(len(validations), 4)
        files = [arg for call in validations for arg in call["args"]
                 if arg.endswith((".yaml", ".yml", "Kustomization"))]
        self.assertEqual(files, [str(self.repo / "resource.yaml")])

    def test_all_kustomization_filenames_propagate_build_failures(self):
        self.env["AUDIT_TEST_BUILD_EXIT"] = "1"
        for filename in ("kustomization.yaml", "kustomization.yml", "Kustomization"):
            with self.subTest(filename=filename):
                config = self.repo / filename
                config.write_text("resources: []\n")
                result = self.run_helper("validate.sh", "-d", str(self.repo))
                config.unlink()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("kustomize build failed", result.stderr)

    def test_exclusions_apply_to_manifests_overlays_and_charts_for_any_target(self):
        target = self.repo / "audit target"
        target.mkdir()
        (target / "resource.yaml").write_text("kind: ConfigMap\n")
        ignored = target / "ignored"
        ignored.mkdir()
        (ignored / "resource.yaml").write_text("kind: ConfigMap\n")
        overlay = ignored / "overlay"
        overlay.mkdir()
        (overlay / "kustomization.yaml").write_text("resources: []\n")
        chart = ignored / "chart"
        chart.mkdir()
        (chart / "Chart.yaml").write_text("apiVersion: v2\nname: fixture\nversion: 1.0.0\n")
        for root in (str(target), "audit target", "./audit target/"):
            for exclusion in ("ignored", "./ignored/", str(ignored)):
                with self.subTest(root=root, exclusion=exclusion):
                    Path(self.env["AUDIT_TEST_LOG"]).write_text("")
                    bundle_file = Path(self.temp.name) / "bundle.yaml"
                    result = self.run_helper("validate.sh", "-e", exclusion,
                                             "-d", root, "-H", "-b", str(bundle_file))
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    calls = self.calls()
                    self.assertFalse(any(call["tool"] in ("kubectl", "helm") for call in calls))
                    validations = [call for call in calls if call["tool"] == "flux-schema"
                                   and call["args"][:1] == ["validate"]]
                    self.assertEqual(len(validations), 1)
                    files = [arg for arg in validations[0]["args"] if arg.endswith(".yaml")]
                    self.assertEqual(files, [str(target / "resource.yaml")])
                    self.assertNotIn("ignored", bundle_file.read_text())

    @unittest.skipUnless(native_kubectl, "kubectl is required for the native containment test")
    def test_native_kustomize_blocks_outside_file_in_output_and_bundle(self):
        self.env["AUDIT_TEST_NATIVE_KUBECTL"] = native_kubectl
        marker = "OUTSIDE_AUDIT_FIXTURE_VALUE"
        outside_file = Path(self.temp.name) / "outside.txt"
        outside_file.write_text(marker)
        config = self.repo / "kustomization.yaml"
        config.write_text("configMapGenerator:\n- name: fixture\n  files:\n  - value=../outside.txt\n")
        bundle_file = Path(self.temp.name) / "bundle.yaml"
        result = self.run_helper("validate.sh", "-d", str(self.repo), "-b", str(bundle_file))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("kustomize build failed", result.stderr)
        self.assertNotIn(marker, result.stdout + result.stderr + bundle_file.read_text())
        # In-root generator files must still render normally.
        (self.repo / "inside.txt").write_text("IN_ROOT_AUDIT_FIXTURE_VALUE")
        config.write_text("configMapGenerator:\n- name: fixture\n  files:\n  - value=inside.txt\n")
        result = self.run_helper("validate.sh", "-d", str(self.repo), "-b", str(bundle_file))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("IN_ROOT_AUDIT_FIXTURE_VALUE", bundle_file.read_text())

    def test_validation_and_build_errors_fail(self):
        self.env["AUDIT_TEST_SCHEMA_EXIT"] = "1"
        self.assertNotEqual(self.run_helper("validate.sh", "-d", ".").returncode, 0)
        self.env["AUDIT_TEST_SCHEMA_EXIT"] = "0"
        (self.repo / "kustomization.yaml").write_text("resources: []\n")
        self.env["AUDIT_TEST_BUILD_EXIT"] = "1"
        self.assertNotEqual(self.run_helper("validate.sh", "-d", ".").returncode, 0)

    def test_documented_setup_resolves_from_another_repository(self):
        if (bundle / "skills/fluxcd/SKILL.md").is_file():
            documents = [bundle / "skills" / name / "SKILL.md"
                         for name in ("fluxcd", "gitops")]
        else:
            documents = [bundle / "SKILL.md"]
        documents += [path for name in ("fluxcd-migration.md", "fluxcd-security.md")
                      if (path := bundle / "references" / name).is_file()]
        for document in documents:
            with self.subTest(document=str(document)):
                blocks = re.findall(r"```bash\n(.*?)```", document.read_text(), re.S)
                setup_index = next(i for i, block in enumerate(blocks)
                                   if "audit_dir=" in block)
                block = blocks[setup_index]
                setup = "\n".join(line for line in block.splitlines()
                                  if line.startswith(("audit_dir=", "SCRIPTS=")))
                setup = setup.replace(
                    "'<absolute path to bundled examples/fluxcd/repo-audit>'",
                    shlex.quote(str(audit_dir)),
                )
                command = next(line for candidate in blocks[setup_index:]
                               for line in candidate.splitlines()
                               if line.startswith("bash "))
                result = subprocess.run([bash, "-c", setup + "\n" + command],
                                        cwd=self.repo, env=self.env,
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


unittest.main(argv=[sys.argv[0]], verbosity=2)
PY

#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("cmux_audit", ROOT / "scripts/cmux-audit.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class AuditTests(unittest.TestCase):
    def rows(self, properties, config, **extra):
        schema = {"properties": properties, **extra}
        return {row["path"]: row for row in audit.audit(schema, config)}

    def test_buckets_null_and_json_equality(self):
        rows = self.rows({"same": {"default": None}, "number": {"default": 1}, "boolean": {"default": True}, "bare": {}},
                         {"same": None, "number": 1.0, "boolean": 1, "bare": "value", "typo": 3})
        self.assertEqual({key: row["status"] for key, row in rows.items()}, {
            "/same": "pinned", "/number": "pinned", "/boolean": "overridden", "/bare": "undeclared", "/typo": "unknown"})
        self.assertIn("default", rows["/same"])
        self.assertNotIn("default", rows["/bare"])

    def test_arrays_and_objects_are_atomic_with_defaults(self):
        props = {"array": {"default": [1, True]}, "map": {"default": {"x": 1}, "properties": {"x": {"default": 2}}}}
        rows = self.rows(props, {"array": [1, 1], "map": {"x": 1}})
        self.assertEqual(rows["/array"]["status"], "overridden")
        self.assertEqual(rows["/map"]["status"], "pinned")
        self.assertEqual(len(rows), 2)
        self.assertFalse(audit.equal([1, 2], [2, 1]))
        self.assertTrue(audit.equal({"a": 1, "b": 2}, {"b": 2, "a": 1}))

    def test_nested_dynamic_and_unknown_properties(self):
        rows = self.rows({"nested": {"properties": {"x/y~z": {"default": 2}}},
                          "map": {"additionalProperties": {"default": False}},
                          "open": {"additionalProperties": True}, "closed": False},
                         {"nested": {"x/y~z": 2}, "map": {"arbitrary": False}, "open": {"custom": {"anything": 4}}, "closed": 1, "missing": {"child": 3}})
        self.assertEqual(rows["/nested/x~1y~0z"]["status"], "pinned")
        self.assertEqual(rows["/map/arbitrary"]["status"], "pinned")
        self.assertEqual(rows["/open/custom"]["status"], "undeclared")
        self.assertEqual(rows["/open/custom"]["value"], {"anything": 4})
        self.assertEqual(rows["/closed"]["status"], "unknown")
        self.assertEqual(rows["/missing/child"]["status"], "unknown")

    def test_open_extension_objects_and_false_ref(self):
        rows = self.rows({"actions": {"additionalProperties": True},
                          "other": {"additionalProperties": {}},
                          "closed": {"$ref": "#/$defs/no"}},
                         {"actions": {"custom": {"command": "hello"}},
                          "other": {"custom": {"nested": {"x": 1}}}, "closed": 1},
                         **{"$defs": {"no": False}})
        self.assertEqual(rows["/actions/custom"]["status"], "undeclared")
        self.assertEqual(rows["/other/custom"]["status"], "undeclared")
        self.assertEqual(rows["/closed"]["status"], "unknown")
        self.assertIn("disallows", rows["/closed"]["note"])
        self.assertEqual(len(rows), 3)

    def test_local_refs_preserve_siblings_and_pointer_escapes(self):
        rows = self.rows({"nullable": {"$ref": "#/$defs/a~1b~0c", "default": None},
                          "inherited": {"$ref": "#/$defs/pinned"}},
                         {"nullable": None, "inherited": 3},
                         **{"$defs": {"a/b~c": {"oneOf": [{"type": "null"}, {"type": "string"}]}, "pinned": {"default": 3}}})
        self.assertEqual(rows["/nullable"]["status"], "pinned")
        self.assertEqual(rows["/inherited"]["status"], "pinned")

    def test_unsupported_refs_and_branch_defaults_do_not_guess(self):
        rows = self.rows({"remote": {"$ref": "https://example.invalid/schema", "default": 1},
                          "cycle": {"$ref": "#/$defs/cycle"},
                          "missing": {"$ref": "#/$defs/missing"},
                          "conflict": {"$ref": "#/$defs/one", "default": 2},
                          "branch": {"oneOf": [{"default": 1}, {"default": 2}]}},
                         {"remote": 1, "cycle": 1, "missing": 1, "conflict": 2, "branch": 1},
                         **{"$defs": {"cycle": {"$ref": "#/$defs/cycle"}, "one": {"default": 1}}})
        self.assertTrue(all(row["status"] == "undeclared" and "note" in row for row in rows.values()))

    def test_empty_containers_and_metadata(self):
        self.assertEqual(audit.audit({}, {}), [])
        rows = self.rows({"empty": {"default": {}}, "array": {"default": []}}, {"$schema": "ignored", "empty": {}, "array": []})
        self.assertEqual(len(rows), 2)
        self.assertTrue(all(row["status"] == "pinned" for row in rows.values()))

    def test_cli_filter_provenance_and_read_only(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            schema = directory / "schema.json"
            config = directory / "config.json"
            schema.write_text(json.dumps({"properties": {"yes": {"default": 1}, "no": {"default": 2}}}))
            config.write_text(json.dumps({"yes": 1, "no": 0, "unknown": True}))
            before = {path.name: (path.read_bytes(), path.stat().st_mtime_ns) for path in directory.iterdir()}
            command = ["bash", str(ROOT / "bin/terminal-kit"), "cmux", "audit", "--schema", str(schema), "--config", str(config)]
            result = subprocess.run(command + ["--json", "--pinned"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            output = json.loads(result.stdout)
            self.assertEqual(output["counts"], {"pinned": 1, "overridden": 1, "undeclared": 0, "unknown": 1})
            self.assertEqual([row["path"] for row in output["rows"]], ["/yes"])
            self.assertEqual(output["schema"], str(schema))
            self.assertEqual(output["config"], str(config))
            self.assertEqual(before, {path.name: (path.read_bytes(), path.stat().st_mtime_ns) for path in directory.iterdir()})
            result = subprocess.run(command + ["--pinned"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('pinned     "/yes"', result.stdout)
            self.assertNotIn('"/no"', result.stdout)

    def test_cli_default_paths_and_errors(self):
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            schema = home / "checkout/web/data/cmux.schema.json"
            schema.parent.mkdir(parents=True)
            schema.write_text('{"properties":{"x":{"default":1}}}')
            config = home / ".config/cmux/cmux.json"
            config.parent.mkdir(parents=True)
            config.write_text('{"x":1}')
            env = {**os.environ, "HOME": str(home), "TERMINAL_KIT_CMUX_DIR": str(home / "checkout")}
            command = ["bash", str(ROOT / "bin/terminal-kit"), "cmux", "audit", "--json"]
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["counts"]["pinned"], 1)
            for contents in ['{', '[]', '{"x":1,"x":2}', '{"x":NaN}', '{"x":1e999}']:
                config.write_text(contents)
                result = subprocess.run(command, env=env, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("terminal-kit: error: cmux audit:", result.stderr)
                self.assertNotIn("Traceback", result.stderr)
            config.unlink()
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("cmux.json", result.stderr)
            self.assertFalse(config.exists())


if __name__ == "__main__":
    unittest.main()

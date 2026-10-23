from pathlib import Path
import re
import unittest


CONFIG = Path(__file__).parents[1] / "nginx/conf.d/default.conf"
SERVER_BLOCKS = re.findall(r"(?ms)^server\s*\{(.*?^\})", CONFIG.read_text())


def server_for(name: str, exact_names: str | None = None) -> str:
    for block in SERVER_BLOCKS:
        if exact_names and re.search(rf"(?m)^\s*server_name\s+{re.escape(exact_names)}\s*;", block):
            return block
        if not exact_names and re.search(rf"(?m)^\s*server_name\s+[^;]*\b{re.escape(name)}\b[^;]*;", block):
            return block
    raise AssertionError(f"No server block for {name}")


class BrowserRoutesTest(unittest.TestCase):
    def test_main_host_uses_normal_frontend_route_for_sandbox(self):
        main = server_for("hanasand.com", "hanasand.com www.hanasand.com")
        self.assertIn("proxy_pass http://localhost:3000;", main)
        self.assertNotRegex(main, r"location\s+(?:=\s*)?/(?:sandbox|api/browser)(?:/|\s|\{)")

    def test_browser_host_keeps_api_and_redirects_website_paths_to_443(self):
        browser = server_for("browsers.hanasand.com")
        self.assertRegex(browser, r"location\s*=\s*/api\s*\{[^}]*proxy_pass http://127\.0\.0\.1:8185/api;")
        self.assertRegex(browser, r"location\s+\^~\s+/api/\s*\{[^}]*proxy_pass http://127\.0\.0\.1:8185;")
        self.assertIn("return 301 https://hanasand.com/sandbox;", browser)
        self.assertIn("return 301 https://hanasand.com/login;", browser)
        self.assertNotRegex(browser, r"return\s+\d+\s+[^;]*:8443")
        self.assertNotIn("/sandbox/login", CONFIG.read_text())

    def test_api_has_no_extra_public_hostname(self):
        self.assertFalse(any("api.browsers.hanasand.com" in block for block in SERVER_BLOCKS))


if __name__ == "__main__":
    unittest.main()

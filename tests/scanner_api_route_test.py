from pathlib import Path
import re
import unittest


CONFIG = Path(__file__).parents[1] / "nginx/conf.d/default.conf"


class ScannerApiRouteTest(unittest.TestCase):
    def test_api_proxy_preserves_public_prefix(self):
        config = CONFIG.read_text()
        servers = re.findall(r"(?ms)^server\s*\{(.*?)^\}", config)
        block = next(
            (server for server in servers if "server_name scanner.hanasand.com;" in server),
            None,
        )
        self.assertIsNotNone(block)

        api_location = re.search(
            r"location \^~ /api/\s*\{(?P<body>.*?)\n\s*\}", block, re.DOTALL
        )
        self.assertIsNotNone(api_location)
        self.assertRegex(
            api_location.group("body"),
            r"proxy_pass\s+http://127\.0\.0\.1:18200\s*;",
        )
        self.assertNotRegex(api_location.group("body"), r"proxy_pass[^;]*/\s*;")


if __name__ == "__main__":
    unittest.main()

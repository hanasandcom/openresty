from pathlib import Path
import re
import unittest


CONFIG = Path(__file__).parents[1] / "nginx/conf.d/ti.hanasand.com.conf"


class ThreatIntelligenceRouteTest(unittest.TestCase):
    def test_ti_host_routes_to_the_standalone_ti_web_and_api_service(self):
        config = CONFIG.read_text()
        self.assertRegex(config, r"(?m)^\s*server_name ti\.hanasand\.com;")
        self.assertRegex(config, r"(?m)^\s*proxy_pass http://127\.0\.0\.1:18080;")
        self.assertIn("include snippets/proxy-headers.conf;", config)
        self.assertNotRegex(config, r"(?m)^\s*return\s+301\s+https://hanasand\.com")


if __name__ == "__main__":
    unittest.main()

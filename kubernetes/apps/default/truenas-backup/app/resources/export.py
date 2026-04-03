# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "truenas_api_client @ https://github.com/truenas/api_client/archive/refs/tags/TS-25.10.2.tar.gz",
# ]
# ///

import os
from pathlib import Path
import ssl
import time
import urllib.request

from truenas_api_client import Client

# Configuration from environment variables
host = os.getenv("TRUENAS_HOST", "").rstrip("/")
api_key = os.getenv("TRUENAS_API_KEY")
# Convert string input to a Path object
output_dir = Path(os.getenv("OUTPUT_DIR", ".")).resolve()

def backup_truenas():
    # 1. Initialize the Client for RPC calls
    with Client(f"wss://{host}/api/current", verify_ssl=False) as client:
        print("Authenticating with TrueNAS API...")
        client.call("auth.login_with_api_key", api_key)

        print("Fetching TrueNAS version...")
        version = client.call("system.version")

        # Use Path object to generate the final filename
        timestamp = time.strftime("%Y%m%d%H%M%S")
        filename = f"config-{version}-{timestamp}.tar"
        output_path = output_dir / filename

        print(f"Requesting config export for version {version}...")

        # 2. Trigger core.download via RPC
        _, download_url = client.call(
            "core.download",
            "config.save",
            [{"secretseed": True, "root_authorized_keys": True}],
            "truenas_config.tar"
        )
        print(f"Download URL received: {download_url}")

        # 3. Download the file using urllib
        full_url = f"https://{host}{download_url}"
        print(f"Downloading to {output_path}...")

        # Ensure the output directory exists
        output_dir.mkdir(parents=True, exist_ok=True)

        req = urllib.request.Request(full_url)
        req.add_header("Authorization", f"Bearer {api_key}")

        # Stream the file to disk using the Path object
        with urllib.request.urlopen(req, context=ssl._create_unverified_context()) as response:
            with output_path.open('wb') as out_file:
                while True:
                    chunk = response.read(16384)
                    if not chunk:
                        break
                    out_file.write(chunk)

        print(f"Export complete: {output_path}")

if __name__ == "__main__":
    if not host or not api_key:
        raise ValueError("Error: TRUENAS_HOST and TRUENAS_API_KEY must be set.")

    backup_truenas()

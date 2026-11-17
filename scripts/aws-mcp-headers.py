"""Native HTTP-header helper for AWS MCP; no server, token file, or login UI.

Use an existing automatically renewable AWS profile, such as IAM Roles Anywhere.
The coding host caches these headers and re-runs the helper on expiration.
Never run this command in a terminal whose output is recorded: stdout is a credential.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def get_headers(profile, region, aws_cli):
    executable = str(Path(aws_cli).resolve()) if aws_cli else shutil.which("aws")
    if not executable or not Path(executable).is_file():
        raise RuntimeError("AWS CLI is unavailable")
    environment = dict(os.environ)
    # An explicit profile must not silently turn into a different account because
    # the coding host inherited temporary credentials or an endpoint override.
    for key in list(environment):
        if key in {
            "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN",
            "AWS_SECURITY_TOKEN", "AWS_ROLE_ARN", "AWS_ROLE_SESSION_NAME",
            "AWS_WEB_IDENTITY_TOKEN_FILE", "AWS_PROFILE", "AWS_DEFAULT_PROFILE",
            "AWS_CONFIG_FILE", "AWS_SHARED_CREDENTIALS_FILE",
            "AWS_BEARER_TOKEN_SIGNIN", "AWS_BEARER_TOKEN_AWS_MCP",
        } or key.startswith("AWS_ENDPOINT_URL"):
            environment.pop(key)
    environment["AWS_CONFIG_FILE"] = str(Path.home() / ".aws" / "config")
    environment["AWS_SHARED_CREDENTIALS_FILE"] = str(Path.home() / ".aws" / "credentials")
    environment["AWS_PAGER"] = ""
    command = [
        executable, "signin", "create-oauth2-token-with-iam",
        "--grant-type", "client_credentials", "--resource", "aws-mcp.amazonaws.com",
        "--region", region, "--profile", profile, "--output", "json", "--no-cli-pager",
        "--cli-connect-timeout", "3", "--cli-read-timeout", "5",
    ]
    result = subprocess.run(
        command, capture_output=True, text=True, timeout=8,
        env=environment, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    if result.returncode:
        raise RuntimeError("AWS profile token grant failed")
    grant = json.loads(result.stdout)
    token = grant.get("accessToken")
    if not isinstance(token, str) or not token or any(ord(c) < 33 or ord(c) == 127 for c in token):
        raise RuntimeError("AWS returned an invalid token")
    if not isinstance(grant.get("expiresIn"), (int, float)) or grant["expiresIn"] < 60:
        raise RuntimeError("AWS returned an expired token")
    return {"Authorization": "Bearer " + token}


def main():
    parser = argparse.ArgumentParser(description="Generate native AWS MCP HTTP authentication headers")
    parser.add_argument("--profile", required=True)
    parser.add_argument("--region", default="us-east-1")
    parser.add_argument("--aws-cli")
    args = parser.parse_args()
    try:
        headers = get_headers(args.profile, args.region, args.aws_cli)
    except Exception:
        # CLI stderr and JSON parser exceptions can contain credentials. Native
        # hosts display helper failures, so emit only this fixed diagnostic.
        print("AWS MCP authentication failed; check the selected native AWS profile.", file=sys.stderr)
        return 1
    print(json.dumps(headers))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Save a native Studio MCP frame for visual review (no scene or script edits)."""
from pathlib import Path
import argparse
import base64
import importlib.util

spec = importlib.util.spec_from_file_location("mcp_sync", Path(__file__).with_name("mcp_sync.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
Mcp = module.Mcp


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--camera", type=float, nargs=3)
    parser.add_argument("--look", type=float, nargs=3)
    args = parser.parse_args()
    if bool(args.camera) != bool(args.look):
        parser.error("--camera and --look must be provided together")
    mcp = Mcp()
    try:
        sid = mcp.studio_id()
        capture = {"studio_id": sid, "capture_id": "ScreenCapture_" + args.output.stem.replace("-", "_")}
        if args.camera:
            capture.update(camera_position=args.camera, look_at_position=args.look)
        result = mcp.request("tools/call", {"name": "screen_capture", "arguments": capture}, timeout=30)
        if result.get("isError"):
            raise RuntimeError(result)
        for content in result.get("content", []):
            if content.get("type") == "image":
                args.output.parent.mkdir(parents=True, exist_ok=True)
                args.output.write_bytes(base64.b64decode(content["data"]))
                print(f"Saved {args.output}")
                return
        raise RuntimeError("Studio returned no image")
    finally:
        mcp.close()


if __name__ == "__main__":
    main()

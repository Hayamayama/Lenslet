from pathlib import Path
import argparse
import signal
import subprocess
import sys
import time


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = PROJECT_ROOT / "data"

LIGHTWEIGHT_MODULES = [
    "lenslet_core.ingest.watch_convert",
    "lenslet_core.ingest.vision_router",
]

FULL_MODULES = [
    "lenslet_core.ingest.watch_convert",
    "lenslet_core.ingest.vision_router",
    "lenslet_core.ingest.vision_worker_v2",
]

processes: list[tuple[str, subprocess.Popen]] = []



def start_module(module_name: str):

    print(f"啟動：{module_name}")

    process = subprocess.Popen(
        [
            sys.executable,
            "-m",
            module_name
        ],
        cwd=str(PROJECT_ROOT),
    )

    processes.append(
        (module_name, process)
    )


def stop_all_processes():
    print("\n正在停止 pipeline...")

    for script_name, process in processes:
        if process.poll() is None:
            print(f"停止：{script_name}")
            process.terminate()

    time.sleep(1)

    for script_name, process in processes:
        if process.poll() is None:
            print(f"強制停止：{script_name}")
            process.kill()

    print("Pipeline 已停止。")


def handle_shutdown_signal(signum, frame):
    stop_all_processes()
    sys.exit(0)


def print_status():
    folders = {
    "documents": DATA_DIR / "inbox" / "documents",
    "md_output": DATA_DIR / "md_output",
    "processed": DATA_DIR / "processed",
    "chunks": DATA_DIR / "chunks",
    "metadata": DATA_DIR / "metadata",
    "vision_queue": DATA_DIR / "vision_queue",
    "vision_output": DATA_DIR / "vision_output",
    "vision_done": DATA_DIR / "vision_done",
    "failed": DATA_DIR / "failed",
    "vision_failed": DATA_DIR / "vision_failed",
}

    print("\n目前資料夾狀態：")

    for name, folder in folders.items():
        if not folder.exists():
            print(f"- {name}: 不存在")
            continue

        file_count = len([p for p in folder.iterdir() if p.is_file()])
        print(f"- {name}: {file_count} files")


def monitor_processes():
    while True:
        for script_name, process in processes:
            return_code = process.poll()

            if return_code is not None:
                print(f"\n警告：{script_name} 已停止，exit code: {return_code}")
                print("為了避免狀態混亂，請 Ctrl + C 停止整個 pipeline 後再重開。")

        time.sleep(2)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Run the document ingestion pipeline from one terminal."
    )

    parser.add_argument(
        "--full",
        action="store_true",
        help="Also start vision_worker_v2.py. This may consume much more power.",
    )

    parser.add_argument(
        "--status",
        action="store_true",
        help="Print folder status before starting the pipeline.",
    )

    return parser.parse_args()


def main():
    args = parse_args()

    signal.signal(signal.SIGINT, handle_shutdown_signal)
    signal.signal(signal.SIGTERM, handle_shutdown_signal)

    modules = FULL_MODULES if args.full else LIGHTWEIGHT_MODULES

    print("啟動 document ingestion pipeline")
    print(f"專案位置：{PROJECT_ROOT}")

    if args.full:
        print("模式：FULL，會啟動 vision_worker_v2.py，耗電會明顯增加。")
    else:
        print("模式：LIGHT，只啟動 watch_convert.py + vision_router.py。")
        print("需要 OCR / Vision 分析時，再另外手動跑 vision_worker_v2.py。")

    if args.status:
        print_status()


    print("\n開始啟動 scripts...")

    for module in modules:
        start_module(module)

    print("\nPipeline 已啟動。按 Ctrl + C 可以一次停止全部。")

    try:
        monitor_processes()
    finally:
        stop_all_processes()


if __name__ == "__main__":
    main()
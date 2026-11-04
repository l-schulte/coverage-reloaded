import time
import threading
import concurrent.futures
from src.collect_coverage import LaunchThrottle
from src.config import load_config, CoverageReloadedConfig


def test_launch_throttle_first_launch_immediate():
    throttle = LaunchThrottle(interval=10.0)
    t0 = time.time()
    throttle.wait()
    t1 = time.time()
    # First launch should not wait
    assert t1 - t0 < 0.2


def test_launch_throttle_zero_or_negative_interval():
    throttle = LaunchThrottle(interval=0.0)
    t0 = time.time()
    throttle.wait()
    throttle.wait()
    t1 = time.time()
    assert t1 - t0 < 0.2

    neg_throttle = LaunchThrottle(interval=-5.0)
    assert neg_throttle.interval == 0.0


def test_launch_throttle_staggered_concurrent():
    interval = 0.1
    throttle = LaunchThrottle(interval=interval)
    start_times = []
    lock = threading.Lock()

    def run():
        throttle.wait()
        with lock:
            start_times.append(time.time())

    threads = [threading.Thread(target=run) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert len(start_times) == 4
    start_times.sort()
    for i in range(1, len(start_times)):
        diff = start_times[i] - start_times[i - 1]
        # Should be at least ~0.09s apart
        assert diff >= interval * 0.85, f"Interval between {i-1} and {i} was {diff:.3f}s"


def test_launch_throttle_no_delay_if_elapsed():
    interval = 0.05
    throttle = LaunchThrottle(interval=interval)
    throttle.wait()
    # Sleep longer than the interval
    time.sleep(0.08)
    t0 = time.time()
    throttle.wait()
    t1 = time.time()
    # Should not wait
    assert t1 - t0 < 0.02


def test_config_launch_delay_default():
    cfg = CoverageReloadedConfig()
    assert cfg.launch_delay == 10.0


def test_load_config_parses_launch_delay(tmp_path):
    config_file = tmp_path / "config.json"
    config_file.write_text('{"launch_delay": 15.5, "projects": {}}')
    cfg = load_config(str(config_file))
    assert cfg.launch_delay == 15.5

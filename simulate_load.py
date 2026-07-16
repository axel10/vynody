#!/usr/bin/env python3
import os
import sys
import time
import random
import tempfile
import threading
import multiprocessing
import signal
from multiprocessing import Process, Event

# Ensure multiprocessing works nicely on macOS (uses spawn by default)
multiprocessing.freeze_support()

def sigterm_handler(signum, frame):
    # Raise KeyboardInterrupt to trigger cleanup and graceful shutdown
    raise KeyboardInterrupt

signal.signal(signal.SIGTERM, sigterm_handler)

def cpu_load_worker(target_utilization, duration, stop_event):
    """
    Generate target CPU utilization on one core.
    target_utilization is a float between 0.0 and 1.0.
    """
    try:
        interval = 0.1  # 100ms slices
        work_duration = interval * target_utilization
        sleep_duration = interval * (1.0 - target_utilization)
        start_time = time.time()
        
        while not stop_event.is_set():
            if duration and (time.time() - start_time) > duration:
                break
            
            loop_start = time.time()
            # Busy loop to simulate CPU load
            while time.time() - loop_start < work_duration:
                # Simple math to keep CPU busy
                _ = 12345.67 * 76543.21
                
            if sleep_duration > 0:
                time.sleep(sleep_duration)
    except KeyboardInterrupt:
        pass

class ResourceSimulator:
    def __init__(self):
        self.cpu_processes = []
        self.stop_events = []
        self.memory_chunks = []
        self.io_threads = []
        self.io_stop_event = threading.Event()
        self.temp_dir = tempfile.gettempdir()
        self.max_cores = os.cpu_count() or 4

    def start_cpu_stress(self, num_cores, utilization, duration=None):
        """
        Start CPU stress on specified number of cores with target utilization.
        """
        cores_to_use = min(max(1, num_cores), self.max_cores)
        print(f"   [CPU] Activating {cores_to_use} cores at {utilization*100:.0f}% load...")
        
        for _ in range(cores_to_use):
            stop_event = Event()
            p = Process(target=cpu_load_worker, args=(utilization, duration, stop_event))
            p.daemon = True
            p.start()
            self.cpu_processes.append(p)
            self.stop_events.append(stop_event)

    def stop_cpu_stress(self):
        if self.cpu_processes:
            print("   [CPU] Stopping CPU stress...")
            for stop_event in self.stop_events:
                stop_event.set()
            for p in self.cpu_processes:
                p.join(timeout=0.2)
                if p.is_alive():
                    p.terminate()
            self.cpu_processes.clear()
            self.stop_events.clear()

    def start_memory_stress(self, mb_size, duration=None):
        """
        Allocate memory and keep it resident.
        """
        mb_size = max(50, mb_size)
        print(f"   [Memory] Allocating ~{mb_size} MB of RAM...")
        chunk_size = 10 * 1024 * 1024  # 10 MB chunks
        num_chunks = int(mb_size / 10)
        
        # Allocate memory in a separate thread to avoid blocking main program
        def allocate_and_hold():
            try:
                for i in range(num_chunks):
                    # Allocate chunk
                    chunk = bytearray(chunk_size)
                    # Touch elements to force physical RAM allocation (RSS)
                    chunk[0] = 42
                    chunk[-1] = 42
                    self.memory_chunks.append(chunk)
                    if i % 10 == 0:
                        time.sleep(0.01)
                print(f"   [Memory] Successfully allocated and holding {len(self.memory_chunks) * 10} MB.")
            except MemoryError:
                print("   [Memory] Memory allocation hit system limit!")
                
        t = threading.Thread(target=allocate_and_hold)
        t.daemon = True
        t.start()

    def stop_memory_stress(self):
        if self.memory_chunks:
            print(f"   [Memory] Releasing {len(self.memory_chunks) * 10} MB of RAM...")
            self.memory_chunks.clear()

    def _io_worker(self, target_mb, stop_event):
        temp_files = []
        chunk = os.urandom(1024 * 1024)  # 1MB buffer
        try:
            while not stop_event.is_set():
                # Write phase
                fd, path = tempfile.mkstemp(dir=self.temp_dir, prefix="vynody_stress_io_")
                temp_files.append(path)
                os.close(fd)
                
                with open(path, "wb") as f:
                    for _ in range(target_mb):
                        if stop_event.is_set():
                            break
                        f.write(chunk)
                        f.flush()
                        os.fsync(f.fileno())  # force disk flush
                        time.sleep(0.005)
                
                # Read phase
                with open(path, "rb") as f:
                    while f.read(1024 * 1024):
                        if stop_event.is_set():
                            break
                        time.sleep(0.005)
                
                # Cleanup old files
                while len(temp_files) > 2:
                    oldest = temp_files.pop(0)
                    if os.path.exists(oldest):
                        os.remove(oldest)
                        
                time.sleep(0.1)
        finally:
            for path in temp_files:
                if os.path.exists(path):
                    try:
                        os.remove(path)
                    except:
                        pass

    def start_io_stress(self, write_size_mb):
        """
        Start disk I/O operations.
        """
        write_size_mb = max(2, write_size_mb)
        print(f"   [I/O] Simulating disk read/write ({write_size_mb} MB cycles)...")
        self.io_stop_event.clear()
        t = threading.Thread(target=self._io_worker, args=(write_size_mb, self.io_stop_event))
        t.daemon = True
        t.start()
        self.io_threads.append(t)

    def stop_io_stress(self):
        if self.io_threads:
            print("   [I/O] Stopping disk I/O stress...")
            self.io_stop_event.set()
            for t in self.io_threads:
                t.join(timeout=1.0)
            self.io_threads.clear()

    def cleanup(self):
        self.stop_cpu_stress()
        self.stop_memory_stress()
        self.stop_io_stress()

    def run_scenario(self, name):
        print(f"\n>>> Starting Preset Scenario: [{name}] <<<")
        
        if name == "browser":
            # Opening browser: Spike CPU to 75% on half of available cores initially, then drop to 20% on 2 cores
            cores = max(2, self.max_cores // 2)
            self.start_cpu_stress(num_cores=cores, utilization=0.75)
            self.start_memory_stress(mb_size=800)
            self.start_io_stress(write_size_mb=10)  # Halved again from 20
            time.sleep(3.0)
            self.stop_cpu_stress()
            self.start_cpu_stress(num_cores=2, utilization=0.25)
            time.sleep(5.0)
            
        elif name == "ide":
            # Opening IDE: Spike CPU to 90%+ on 75% of available cores (indexing), heavy memory, heavy I/O
            cores = max(3, int(self.max_cores * 0.75))
            self.start_cpu_stress(num_cores=cores, utilization=0.92)
            self.start_memory_stress(mb_size=2000)
            self.start_io_stress(write_size_mb=35)  # Halved again from 75
            time.sleep(7.0)
            self.stop_cpu_stress()
            self.stop_io_stress()
            # Idle IDE background tasks
            self.start_cpu_stress(num_cores=2, utilization=0.3)
            time.sleep(8.0)
            
        elif name == "video_editor":
            # Rendering video: Absolute maximum load (100%) on ALL available CPU cores, massive RAM/IO
            self.start_cpu_stress(num_cores=self.max_cores, utilization=0.98)
            self.start_memory_stress(mb_size=4500)
            self.start_io_stress(write_size_mb=100)  # Halved again from 200
            time.sleep(20.0)
            self.stop_cpu_stress()
            self.stop_io_stress()
            self.start_cpu_stress(num_cores=3, utilization=0.4)
            time.sleep(5.0)
            
        self.cleanup()
        print(f">>> Preset Scenario [{name}] Finished <<<\n")

    def run_auto_mode(self):
        """
        Unattended, randomized background simulation mode (Heavier Profile, Halved again I/O).
        """
        print("=" * 60)
        print("       Vynody Stress Driver: AUTOMATED UNATTENDED MODE (HEAVY)")
        print(f"       System: macOS | Max CPU Cores: {self.max_cores}")
        print("       Running heavy/aggressive background tasks at random intervals...")
        print("       Press Ctrl+C to terminate.")
        print("=" * 60)
        
        cycle_count = 0
        try:
            while True:
                cycle_count += 1
                # 1. Decide event type
                event_type = random.choice(["preset", "custom_spike", "idle"])
                
                print(f"\n[Cycle #{cycle_count}] Time: {time.strftime('%H:%M:%S')}")
                
                if event_type == "preset":
                    preset = random.choice(["browser", "ide", "video_editor"])
                    print(f"-> Selected Preset Workload: [{preset}]")
                    self.run_scenario(preset)
                    
                elif event_type == "custom_spike":
                    # Generate an aggressive resource load
                    # Use at least half of the available CPU cores up to 100% of cores
                    min_cores = max(1, self.max_cores // 2)
                    cores = random.randint(min_cores, self.max_cores)
                    # Force utilization to be high (75% to 100%)
                    util = round(random.uniform(0.75, 1.00), 2)
                    ram_mb = random.choice([500, 1000, 2000, 3500, 5000])
                    io_mb = random.choice([0, 12, 35, 75, 125])  # Halved again from [0, 25, 75, 150, 250]
                    duration = random.randint(8, 30)
                    
                    print(f"-> Generating Heavy Custom Spike: Cores={cores}/{self.max_cores}, CPU={util*100:.0f}%, RAM={ram_mb}MB, I/O={io_mb}MB for {duration} seconds.")
                    self.start_cpu_stress(cores, util)
                    self.start_memory_stress(ram_mb)
                    if io_mb > 0:
                        self.start_io_stress(io_mb)
                        
                    time.sleep(duration)
                    self.cleanup()
                    print(f"-> Custom Spike completed. Released resources.")
                    
                else:
                    # Idle / Cool-down phase
                    duration = random.randint(8, 30)
                    print(f"-> Entering Idle/Cool-down phase for {duration} seconds (No stress).")
                    time.sleep(duration)
                
                # Sleep a random short interval before the next cycle
                next_delay = random.randint(3, 12)
                print(f"Waiting {next_delay} seconds before next workload cycle...")
                time.sleep(next_delay)
                
        except KeyboardInterrupt:
            self.cleanup()
            print("\nAutomated mode terminated by user.")

def menu(simulator):
    print("=" * 60)
    print("       Vynody Playback Resource Stress Simulator")
    print(f"       System: macOS | Available CPU Cores: {simulator.max_cores}")
    print("=" * 60)
    print("Select a scenario to simulate user daily activities:")
    print("  [1] Open Browser (Moderate load: 800MB RAM, brief 50%+ CPU spike)")
    print("  [2] Open IDE / Indexing (Heavy load: 2.0GB RAM, 75% core 92% CPU indexing spike)")
    print("  [3] Video Rendering (Extreme load: 4.5GB RAM, Max-core 98% CPU, sustained disk write/read)")
    print("  [4] Custom Continuous Stress (Run until you press Ctrl+C)")
    print("  [5] AUTOMATED UNATTENDED MODE (HEAVY - Loops forever, random heavy loads)")
    print("  [q] Quit")
    print("-" * 60)
    
    while True:
        try:
            choice = input("Enter option (1/2/3/4/5/q): ").strip().lower()
            if choice == '1':
                simulator.run_scenario("browser")
            elif choice == '2':
                simulator.run_scenario("ide")
            elif choice == '3':
                simulator.run_scenario("video_editor")
            elif choice == '4':
                print("\nStarting custom continuous stress. Press Ctrl+C to stop.")
                cores = int(input(f"Number of cores to stress (1-{simulator.max_cores}): ").strip() or "2")
                cpu_util = float(input("CPU utilization (0.1 - 1.0, default 0.8): ").strip() or "0.8")
                ram_mb = int(input("RAM allocation in MB (default 1500): ").strip() or "1500")
                io_mb = int(input("I/O stress size in MB (0 to disable, default 25): ").strip() or "25")  # Halved again from 50
                
                print("\n>>> Custom Stress Running... <<<")
                simulator.start_cpu_stress(cores, cpu_util)
                simulator.start_memory_stress(ram_mb)
                if io_mb > 0:
                    simulator.start_io_stress(io_mb)
                
                while True:
                    time.sleep(1.0)
            elif choice == '5':
                simulator.run_auto_mode()
            elif choice == 'q':
                break
            else:
                print("Invalid option. Please try again.")
        except KeyboardInterrupt:
            simulator.cleanup()
            print("\nStress stopped by user.")
        print("\n" + "=" * 60)
        print("Select a scenario to simulate user daily activities:")
        print("  [1] Open Browser")
        print("  [2] Open IDE")
        print("  [3] Video Rendering")
        print("  [4] Custom Continuous Stress")
        print("  [5] AUTOMATED UNATTENDED MODE")
        print("  [q] Quit")
        print("-" * 60)

if __name__ == '__main__':
    simulator = ResourceSimulator()
    try:
        if len(sys.argv) > 1:
            arg = sys.argv[1].lower()
            if arg in ["auto", "--auto", "-a", "5"]:
                simulator.run_auto_mode()
            elif arg in ["browser", "1"]:
                simulator.run_scenario("browser")
            elif arg in ["ide", "2"]:
                simulator.run_scenario("ide")
            elif arg in ["video", "video_editor", "3"]:
                simulator.run_scenario("video_editor")
            else:
                print(f"Unknown option '{arg}'. Running menu instead.")
                menu(simulator)
        else:
            menu(simulator)
    except KeyboardInterrupt:
        simulator.cleanup()
        print("\nExited.")
    sys.exit(0)

/**
 * @brief Utility for grouped Linux perf event measurement.
 *
 * This module defines `PerfGroup`, a small RAII-style helper that opens hardware/cache
 * performance counters via `perf_event_open`, groups them under a single leader so they
 * start/stop simultaneously, and exposes methods to initialize common events, control
 * measurement windows, and read per-event counts.
 *
 * Syscall documentation: https://man7.org/linux/man-pages/man2/perf_event_open.2.html
 */
#pragma once
#include <linux/perf_event.h>
#include <sys/syscall.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <vector>
#include <cstring>
#include <string>

class PerfGroup
{
public:
	struct Event
	{
		int fd; // https://en.wikipedia.org/wiki/File_descriptor
		std::string name;
	};
	// Perf events need to be grouped together to ensure they are measured simultaneously.
	// The first added event becomes the group leader, and all subsequent events are added to this group.
	// This grouping is handled by the OS in the syscall in the add_event() method.
	std::vector<Event> events;
	int leader_fd = -1;

	void add_event(uint32_t type, uint64_t config, std::string name)
	{
		perf_event_attr attr;
		std::memset(&attr, 0, sizeof(attr)); // Zero out the structure to ensure all fields are initialized as otherwise they might contain garbage values
		attr.type = type;					 // Type of the event (e.g., hardware, software, cache, etc.)
		attr.size = sizeof(attr);			 // Size of the perf_event_attr structure
		attr.config = config;				 // Specific event to monitor (e.g., CPU cycles, instructions, cache misses, etc.)
		attr.disabled = 1;					 // Start in a disabled state; we will enable it later with ioctl, thus we can isolate measurements
		attr.inherit = 1;					 // Inherit event counters to child processes (openMP threads)
		attr.exclude_kernel = 1;			 // Exclude events that occur in kernel mode
		attr.exclude_hv = 1;				 // Exclude events that occur in hypervisor mode

		//"glibc provides no wrapper for perf_event_open(), necessitating the use of syscall(2)." (perf_event_open manual)
		int fd = syscall(__NR_perf_event_open, &attr, 0, -1, leader_fd, 0); // pid=0 (self), cpu=-1 (all CPUs), group_fd=leader_fd (grouping events), flags=0
		if (fd == -1)
		{
			perror("perf_event_open failed");
			return;
		}
		if (leader_fd == -1) // The first added event becomes the group leader
			leader_fd = fd;
		events.push_back({fd, name});
	}

	// Needs to be called immediately before the measured code section. Resets and starts all event measurements in the group simultaneously.
	void start()
	{
		ioctl(leader_fd, PERF_EVENT_IOC_RESET, PERF_IOC_FLAG_GROUP);
		ioctl(leader_fd, PERF_EVENT_IOC_ENABLE, PERF_IOC_FLAG_GROUP);
	}

	// Needs to be called immediately after the measured code section to stop the measurements.
	void stop()
	{
		ioctl(leader_fd, PERF_EVENT_IOC_DISABLE, PERF_IOC_FLAG_GROUP);
	}

	// Reads the value of a specific event file descriptor. Can be called after stop() to get the final count for that event.
	long long get_value(int fd)
	{
		long long val;
		if (read(fd, &val, sizeof(long long)) == -1)
			return -1;
		return val;
	}

	void initialize_std_events()
	{
		// Events are defined in perf_event.h by the Linux kernel
		add_event(PERF_TYPE_HARDWARE, PERF_COUNT_HW_CPU_CYCLES, "cycles");
		add_event(PERF_TYPE_HARDWARE, PERF_COUNT_HW_INSTRUCTIONS, "instructions");
		add_event(PERF_TYPE_HARDWARE, PERF_COUNT_HW_CACHE_MISSES, "cache_misses");
		// https://stackoverflow.com/questions/61190033/how-to-measure-the-dtlb-hits-and-dtlb-misses-with-perf-event-open
		// Bits 0-7: dtlb -> 8-15: only read accesses -> 16-23: only misses
		add_event(PERF_TYPE_HW_CACHE, (PERF_COUNT_HW_CACHE_DTLB | (PERF_COUNT_HW_CACHE_OP_READ << 8) | (PERF_COUNT_HW_CACHE_RESULT_MISS << 16)), "dtlb_load_misses");
	}

	// Destructor to close all event file descriptors when the PerfGroup object goes out of scope.
	~PerfGroup()
	{
		for (auto &e : events)
			close(e.fd);
	}
};
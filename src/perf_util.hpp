#ifndef PERF_UTIL_HPP
#define PERF_UTIL_HPP

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
		int fd;
		std::string name;
	};
	std::vector<Event> events;
	int leader_fd = -1;

	void add_event(uint32_t type, uint64_t config, std::string name)
	{
		perf_event_attr attr;
		std::memset(&attr, 0, sizeof(attr));
		attr.type = type;
		attr.config = config;
		attr.size = sizeof(attr);
		attr.disabled = 1;
		attr.inherit = 1;
		attr.exclude_kernel = 1;
		attr.exclude_hv = 1;

		int fd = syscall(__NR_perf_event_open, &attr, 0, -1, leader_fd, 0);
		if (fd == -1)
		{
			perror("perf_event_open failed");
			return;
		}
		if (leader_fd == -1)
			leader_fd = fd;
		events.push_back({fd, name});
	}

	void start()
	{
		if (leader_fd != -1)
		{
			ioctl(leader_fd, PERF_EVENT_IOC_RESET, PERF_IOC_FLAG_GROUP);
			ioctl(leader_fd, PERF_EVENT_IOC_ENABLE, PERF_IOC_FLAG_GROUP);
		}
	}

	void stop()
	{
		if (leader_fd != -1)
		{
			ioctl(leader_fd, PERF_EVENT_IOC_DISABLE, PERF_IOC_FLAG_GROUP);
		}
	}

	long long get_value(int fd)
	{
		long long val;
		if (read(fd, &val, sizeof(long long)) == -1)
			return -1;
		return val;
	}

	~PerfGroup()
	{
		for (auto &e : events)
			close(e.fd);
	}
};

#endif
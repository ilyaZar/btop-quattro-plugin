#define _GNU_SOURCE

#include <dlfcn.h>
#include <errno.h>
#include <glob.h>
#include <linux/perf_event.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#define MAX_EVENTS 64
#define NVML_SUCCESS 0
#define NVML_TEMPERATURE_GPU 0

typedef int nvmlReturn_t;
typedef struct nvmlDevice_st *nvmlDevice_t;

typedef struct {
  unsigned int gpu;
  unsigned int memory;
} nvmlUtilization_t;

struct telemetry {
  const char *backend;
  double usage;
  double temperature;
  bool has_temperature;
};

struct counter {
  int fd;
  uint64_t value;
  uint64_t enabled;
};

struct sample {
  uint64_t value;
  uint64_t enabled;
};

static void *load_symbol(void *library, const char *name) {
  dlerror();
  void *symbol = dlsym(library, name);
  return dlerror() == NULL ? symbol : NULL;
}

static int collect_nvidia(struct telemetry *telemetry) {
  void *library = dlopen("libnvidia-ml.so.1", RTLD_LAZY | RTLD_LOCAL);
  if (library == NULL)
    library = dlopen("libnvidia-ml.so", RTLD_LAZY | RTLD_LOCAL);
  if (library == NULL)
    return -1;

  nvmlReturn_t (*init)(void) = load_symbol(library, "nvmlInit_v2");
  if (init == NULL)
    init = load_symbol(library, "nvmlInit");
  nvmlReturn_t (*shutdown)(void) = load_symbol(library, "nvmlShutdown");
  nvmlReturn_t (*get_count)(unsigned int *) =
      load_symbol(library, "nvmlDeviceGetCount_v2");
  if (get_count == NULL)
    get_count = load_symbol(library, "nvmlDeviceGetCount");
  nvmlReturn_t (*get_device)(unsigned int, nvmlDevice_t *) =
      load_symbol(library, "nvmlDeviceGetHandleByIndex_v2");
  if (get_device == NULL)
    get_device = load_symbol(library, "nvmlDeviceGetHandleByIndex");
  nvmlReturn_t (*get_utilization)(nvmlDevice_t, nvmlUtilization_t *) =
      load_symbol(library, "nvmlDeviceGetUtilizationRates");
  nvmlReturn_t (*get_temperature)(nvmlDevice_t, unsigned int, unsigned int *) =
      load_symbol(library, "nvmlDeviceGetTemperature");

  if (init == NULL || shutdown == NULL || get_count == NULL ||
      get_device == NULL || get_utilization == NULL) {
    dlclose(library);
    return -1;
  }

  if (init() != NVML_SUCCESS) {
    dlclose(library);
    return -1;
  }

  unsigned int count = 0;
  bool found = false;
  nvmlDevice_t selected = NULL;
  if (get_count(&count) == NVML_SUCCESS) {
    for (unsigned int i = 0; i < count; i++) {
      nvmlDevice_t device = NULL;
      nvmlUtilization_t utilization = {0};
      if (get_device(i, &device) != NVML_SUCCESS || device == NULL)
        continue;
      if (get_utilization(device, &utilization) != NVML_SUCCESS ||
          utilization.gpu > 100)
        continue;
      if (!found || utilization.gpu > telemetry->usage) {
        telemetry->usage = utilization.gpu;
        selected = device;
        found = true;
      }
    }
  }

  if (found && get_temperature != NULL) {
    unsigned int temperature = 0;
    if (get_temperature(selected, NVML_TEMPERATURE_GPU, &temperature) ==
            NVML_SUCCESS &&
        temperature > 0 && temperature < 200) {
      telemetry->temperature = temperature;
      telemetry->has_temperature = true;
    }
  }

  shutdown();
  dlclose(library);
  if (!found)
    return -1;

  telemetry->backend = "nvidia";
  return 0;
}

static int perf_event_open(struct perf_event_attr *attr, int cpu) {
  return syscall(SYS_perf_event_open, attr, -1, cpu, -1, 0);
}

static int read_text(const char *path, char *buffer, size_t size) {
  FILE *file = fopen(path, "r");
  if (file == NULL)
    return -1;

  if (fgets(buffer, (int)size, file) == NULL) {
    fclose(file);
    return -1;
  }

  fclose(file);
  return 0;
}

static int parse_number(const char *text, uint64_t *value) {
  errno = 0;
  char *end = NULL;
  unsigned long long parsed = strtoull(text, &end, 0);
  if (errno != 0 || end == text)
    return -1;

  *value = (uint64_t)parsed;
  return 0;
}

static int event_type_path(const char *event_path, char *path, size_t size) {
  const char *events = strstr(event_path, "/events/");
  if (events == NULL)
    return -1;

  size_t root_length = (size_t)(events - event_path);
  if (root_length + sizeof("/type") > size)
    return -1;

  memcpy(path, event_path, root_length);
  memcpy(path + root_length, "/type", sizeof("/type"));
  return 0;
}

static int read_event_definition(const char *event_path, uint32_t *type,
                                 uint64_t *config) {
  char buffer[256];
  char type_path[512];

  if (read_text(event_path, buffer, sizeof(buffer)) != 0)
    return -1;
  char *definition = strstr(buffer, "config=");
  if (definition == NULL || parse_number(definition + 7, config) != 0)
    return -1;

  if (event_type_path(event_path, type_path, sizeof(type_path)) != 0)
    return -1;
  if (read_text(type_path, buffer, sizeof(buffer)) != 0)
    return -1;

  uint64_t parsed_type = 0;
  if (parse_number(buffer, &parsed_type) != 0 || parsed_type > UINT32_MAX)
    return -1;

  *type = (uint32_t)parsed_type;
  return 0;
}

static int open_counter(uint32_t type, uint64_t config) {
  struct perf_event_attr attr = {0};
  attr.type = type;
  attr.size = sizeof(attr);
  attr.config = config;
  attr.read_format = PERF_FORMAT_TOTAL_TIME_ENABLED;

  long cpu_count = sysconf(_SC_NPROCESSORS_CONF);
  if (cpu_count < 1)
    cpu_count = 1;

  for (int cpu = 0; cpu < cpu_count; cpu++) {
    int fd = perf_event_open(&attr, cpu);
    if (fd >= 0)
      return fd;
    if (errno != EINVAL)
      break;
  }

  return -1;
}

static int read_counter(struct counter *counter) {
  struct sample sample = {0};
  ssize_t bytes = read(counter->fd, &sample, sizeof(sample));
  if (bytes != (ssize_t)sizeof(sample))
    return -1;

  counter->value = sample.value;
  counter->enabled = sample.enabled;
  return 0;
}

static void close_counters(struct counter *counters, size_t count) {
  for (size_t i = 0; i < count; i++) {
    if (counters[i].fd >= 0)
      close(counters[i].fd);
  }
}

static size_t discover_counters(struct counter *counters) {
  const char *patterns[] = {
      "/sys/bus/event_source/devices/i915*/events/*-busy",
  };
  size_t count = 0;

  for (size_t pattern = 0; pattern < sizeof(patterns) / sizeof(patterns[0]);
       pattern++) {
    glob_t matches = {0};
    int result = glob(patterns[pattern], 0, NULL, &matches);
    if (result != 0 && result != GLOB_NOMATCH) {
      globfree(&matches);
      continue;
    }

    for (size_t i = 0; i < matches.gl_pathc && count < MAX_EVENTS; i++) {
      uint32_t type = 0;
      uint64_t config = 0;
      if (read_event_definition(matches.gl_pathv[i], &type, &config) != 0)
        continue;

      int fd = open_counter(type, config);
      if (fd < 0)
        continue;
      counters[count++] = (struct counter){.fd = fd};
    }

    globfree(&matches);
  }

  return count;
}

static int collect_intel(struct telemetry *telemetry, int interval_ms) {
  struct counter counters[MAX_EVENTS];
  for (size_t i = 0; i < MAX_EVENTS; i++)
    counters[i].fd = -1;

  size_t count = discover_counters(counters);
  if (count == 0)
    return -1;

  size_t ready = 0;
  for (size_t i = 0; i < count; i++) {
    if (read_counter(&counters[i]) == 0) {
      ready++;
    } else {
      close_counters(counters + i, 1);
      counters[i].fd = -1;
    }
  }
  if (ready == 0) {
    close_counters(counters, count);
    return -1;
  }

  struct timespec delay = {
      .tv_sec = interval_ms / 1000,
      .tv_nsec = (long)(interval_ms % 1000) * 1000000L,
  };
  while (nanosleep(&delay, &delay) != 0) {
    if (errno != EINTR) {
      close_counters(counters, count);
      return -1;
    }
  }

  double maximum = -1.0;
  for (size_t i = 0; i < count; i++) {
    if (counters[i].fd < 0)
      continue;

    uint64_t previous_value = counters[i].value;
    uint64_t previous_enabled = counters[i].enabled;
    if (read_counter(&counters[i]) != 0)
      continue;
    if (counters[i].value < previous_value ||
        counters[i].enabled <= previous_enabled)
      continue;

    uint64_t value_delta = counters[i].value - previous_value;
    uint64_t enabled_delta = counters[i].enabled - previous_enabled;
    double usage = (double)value_delta * 100.0 / (double)enabled_delta;
    if (!isfinite(usage) || usage < 0.0)
      continue;
    if (usage > 100.0)
      usage = 100.0;
    if (usage > maximum)
      maximum = usage;
  }

  close_counters(counters, count);
  if (maximum < 0.0)
    return -1;

  telemetry->backend = "intel";
  telemetry->usage = maximum;
  return 0;
}

static int parse_interval(const char *argument) {
  if (argument == NULL)
    return 100;

  errno = 0;
  char *end = NULL;
  long value = strtol(argument, &end, 10);
  if (errno != 0 || end == argument || *end != '\0' || value < 50 ||
      value > 5000)
    return -1;

  return (int)value;
}

int main(int argc, char **argv) {
  int interval_ms = parse_interval(argc > 1 ? argv[1] : NULL);
  if (interval_ms < 0) {
    fprintf(stderr, "usage: %s [interval-ms: 50..5000]\n", argv[0]);
    return 2;
  }

  struct telemetry telemetry = {
      .backend = NULL,
      .usage = -1.0,
      .temperature = -1.0,
      .has_temperature = false,
  };

  if (collect_nvidia(&telemetry) != 0 &&
      collect_intel(&telemetry, interval_ms) != 0) {
    fprintf(stderr, "no supported GPU telemetry backend\n");
    return 3;
  }

  if (!isfinite(telemetry.usage) || telemetry.usage < 0.0 ||
      telemetry.usage > 100.0)
    return 4;

  printf("backend\t%s\n", telemetry.backend);
  printf("usage\t%.2f\n", telemetry.usage);
  if (telemetry.has_temperature)
    printf("temperature\t%.2f\n", telemetry.temperature);
  return 0;
}

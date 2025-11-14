#pragma once
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <filesystem>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <chrono>
#include <unordered_map>
#include <unordered_set>
#include <map>
#include <set>
#include <algorithm>
#include <functional>
#include <typeindex>
#include <typeinfo>
#include <type_traits>
#include <cstdint>
#include <cassert>
#include <cstring>
#include <cstdlib>
#include <vulkan/vulkan.h>
#include "json.h"

#define FIND_IN_VEC(x, vec) (std::find(vec.begin(), vec.end(), x) != vec.end())
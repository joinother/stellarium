#pragma once

#include <napi/native_api.h>

// Register native 3D detail-model rasterizers onto the N-API module exports.
// Called from both the main thread and ArkTS ThreadWorker environments when
// libentry.so is imported.
void registerDetailModelNapi(napi_env env, napi_value exports);

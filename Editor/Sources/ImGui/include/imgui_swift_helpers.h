#pragma once
#include "imgui.h"

#ifdef __cplusplus
extern "C" {
#endif

ImFont* ImGui_AddFontFromFileTTF(ImFontAtlas* atlas, const char* filename, float size_pixels);
ImFont* ImGui_AddFontDefault(ImFontAtlas* atlas);

#ifdef __cplusplus
}
#endif

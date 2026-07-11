#include "include/imgui_swift_helpers.h"

extern "C" {

ImFont* ImGui_AddFontFromFileTTF(ImFontAtlas* atlas, const char* filename, float size_pixels) {
    return atlas->AddFontFromFileTTF(filename, size_pixels);
}

ImFont* ImGui_AddFontDefault(ImFontAtlas* atlas) {
    return atlas->AddFontDefault();
}

}

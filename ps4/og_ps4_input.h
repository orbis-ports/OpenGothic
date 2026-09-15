// The "connect a keyboard" notice.
//
// The PS4 backend in Tempest reads a USB keyboard and mouse and nothing else: OpenGothic has no
// controller support, and a pad forging keyboard input was dropped rather than maintained. A console
// with no keyboard attached therefore has no input at all, and the only useful thing the title can do
// is say so on screen - over the menus, the loading banner and the world alike.
#pragma once

namespace Tempest {
class VectorImage;
class TextureAtlas;
}

namespace Ps4Og {

// Call once per frame BEFORE deciding whether the ui needs a repaint. True when the notice has just
// appeared or disappeared, which is the caller's cue to update(): the ui layer is not repainted every
// frame, so a notice that only changed state would otherwise stay stale.
bool keyboardNoticeChanged();

// Paint the notice on top of an already painted ui layer, if it is showing.
void keyboardNoticePaint(Tempest::VectorImage& ui, Tempest::TextureAtlas& atlas, int w, int h, float scale);

}

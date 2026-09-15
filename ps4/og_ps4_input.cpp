#include "og_ps4_input.h"

#include <Tempest/Application>
#include <Tempest/Brush>
#include <Tempest/Event>
#include <Tempest/Painter>
#include <Tempest/PS4Api>
#include <Tempest/TextureAtlas>
#include <Tempest/VectorImage>

#include "utils/gthfont.h"
#include "resources.h"

#include <cstdint>

using namespace Tempest;

namespace {

// The backend opens the keyboard on its first poll, and the first reads may come before the device
// has reported in. A notice flashed for one frame on every boot would read as a fault, so absence has
// to last this long before it is shown. Hiding is immediate.
const uint64_t kShowAfterMs = 1000;

uint64_t absentSince = 0;
bool     visible     = false;

}

bool Ps4Og::keyboardNoticeChanged() {
  const bool connected = PS4Api::isKeyboardConnected();
  const uint64_t now   = Application::tickCount();

  bool show = false;
  if(connected) {
    absentSince = 0;
    } else {
    if(absentSince==0)
      absentSince = now;
    show = (now-absentSince>=kShowAfterMs);
    }

  if(show==visible)
    return false;
  visible = show;
  return true;
  }

void Ps4Og::keyboardNoticePaint(VectorImage& ui, TextureAtlas& atlas, int w, int h, float scale) {
  if(!visible)
    return;

  PaintEvent e(ui,atlas,w,h);
  Painter    p(e);

  p.setBrush(Brush(Color(0,0,0,0.8f),Painter::Alpha));
  p.drawRect(0,0,w,h);

  // Plain ASCII: the Gothic fonts are single-byte codepage images, and which codepage depends on the
  // installation the player put on the console.
  static const char* const lines[] = {
    "No keyboard detected",
    "",
    "Connect a USB keyboard to play. A mouse is optional.",
    };

  auto&     fnt   = Resources::font("font_old_20_white.tga",Resources::FontType::Normal,scale);
  const int lineH = fnt.pixelSize()+int(8*scale);
  const int n     = int(sizeof(lines)/sizeof(lines[0]));
  int       y     = (h-n*lineH)/2+fnt.pixelSize();
  for(auto l:lines) {
    const int tw = fnt.textSize(l).w;
    fnt.drawText(p,(w-tw)/2,y,l);
    y += lineH;
    }
  }

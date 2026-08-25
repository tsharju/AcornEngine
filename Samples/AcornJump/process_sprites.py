import os
import math
from PIL import Image, ImageDraw

BRAIN_DIR = "/Users/tsharju/.gemini/antigravity/brain/05ccd4f4-a185-42b5-943b-de0418fcbd47"
SPRITES_DIR = "Samples/AcornJump/assets/sprites"
RESOURCES_DIR = "Samples/AcornJump/AcornJump/Resources"
APPICON_DIR = "Samples/AcornJump/AcornJump/Assets.xcassets/AppIcon.appiconset"

os.makedirs(SPRITES_DIR, exist_ok=True)
os.makedirs(RESOURCES_DIR, exist_ok=True)
os.makedirs(APPICON_DIR, exist_ok=True)

CHARACTERS_IMG = os.path.join(BRAIN_DIR, "acorn_character_sprite_1787482784259.jpg")
PLATFORMS_IMG = os.path.join(BRAIN_DIR, "acorn_game_platforms_1787482798976.jpg")
MONSTERS_IMG = os.path.join(BRAIN_DIR, "acorn_game_monsters_1787482813330.jpg")
POWERUPS_IMG = os.path.join(BRAIN_DIR, "acorn_game_powerups_1787482831247.jpg")
APPICON_IMG = os.path.join(BRAIN_DIR, "acorn_jump_app_icon_1787482845750.jpg")

def remove_white_background(img, threshold=235):
    img = img.convert("RGBA")
    datas = img.getdata()
    newData = []
    for item in datas:
        r, g, b, a = item
        if r > threshold and g > threshold and b > threshold:
            dist = max(255 - r, 255 - g, 255 - b)
            alpha = min(255, int(dist * 6.0))
            if alpha < 20:
                alpha = 0
            newData.append((r, g, b, alpha))
        else:
            newData.append(item)
    img.putdata(newData)
    return img

def crop_and_save(img, box, name, max_size=(256, 256)):
    cropped = img.crop(box)
    bbox = cropped.getbbox()
    if bbox:
        cropped = cropped.crop(bbox)
        pad = 4
        padded = Image.new("RGBA", (cropped.width + pad*2, cropped.height + pad*2), (0, 0, 0, 0))
        padded.paste(cropped, (pad, pad))
        cropped = padded
    if max_size:
        cropped.thumbnail(max_size, Image.Resampling.LANCZOS)
    out_path = os.path.join(SPRITES_DIR, f"{name}.png")
    cropped.save(out_path)
    print(f"Saved {name}.png ({cropped.width}x{cropped.height})")
    return cropped

def process_app_icon():
    if os.path.exists(APPICON_IMG):
        icon = Image.open(APPICON_IMG).convert("RGBA")
        icon = icon.resize((1024, 1024), Image.Resampling.LANCZOS)
        icon_path = os.path.join(APPICON_DIR, "AppIcon-1024x1024.png")
        icon.save(icon_path)
        print("Saved AppIcon-1024x1024.png")
        
        contents_json = """{
  "images" : [
    {
      "filename" : "AppIcon-1024x1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
        with open(os.path.join(APPICON_DIR, "Contents.json"), "w") as f:
            f.write(contents_json)

def process_characters():
    if not os.path.exists(CHARACTERS_IMG):
        return
    img = remove_white_background(Image.open(CHARACTERS_IMG))
    w, h = img.size
    
    idle = crop_and_save(img, (0, 0, w//2, h//2), "acorn_idle", max_size=(256, 256))
    jump = crop_and_save(img, (w//2, 0, w, h//2), "acorn_jump", max_size=(256, 256))
    fall = crop_and_save(img, (0, h//2, w//2, h), "acorn_fall", max_size=(256, 256))
    propeller = crop_and_save(img, (w//2, h//2, w, h), "acorn_propeller", max_size=(256, 256))
    
    shoot = idle.copy()
    draw = ImageDraw.Draw(shoot)
    cx, cy = shoot.width // 2, 10
    draw.polygon([(cx, cy), (cx+8, cy+15), (cx+20, cy+18), (cx+10, cy+25), (cx+14, cy+38), (cx, cy+30), (cx-14, cy+38), (cx-10, cy+25), (cx-20, cy+18), (cx-8, cy+15)], fill=(255, 235, 60))
    shoot.save(os.path.join(SPRITES_DIR, "acorn_shoot.png"))
    
    jetpack = jump.copy()
    draw = ImageDraw.Draw(jetpack)
    fx1, fy1 = jetpack.width // 4, jetpack.height - 10
    fx2, fy2 = jetpack.width * 3 // 4, jetpack.height - 10
    draw.polygon([(fx1 - 6, fy1), (fx1 + 6, fy1), (fx1, fy1 + 22)], fill=(60, 180, 255))
    draw.polygon([(fx2 - 6, fy2), (fx2 + 6, fy2), (fx2, fy2 + 22)], fill=(60, 180, 255))
    jetpack.save(os.path.join(SPRITES_DIR, "acorn_jetpack.png"))

def process_platforms():
    if not os.path.exists(PLATFORMS_IMG):
        return
    img = remove_white_background(Image.open(PLATFORMS_IMG))
    w, h = img.size
    
    crop_and_save(img, (0, 0, w//2 + 50, h//3 + 40), "platform_wood", max_size=(256, 96))
    crop_and_save(img, (w//2 - 40, 0, w, h//3 + 40), "platform_leaf", max_size=(256, 96))
    crop_and_save(img, (w//6, h//3 - 30, w * 5 // 6, h * 2 // 3 + 20), "platform_moving", max_size=(256, 96))
    crop_and_save(img, (0, h * 2 // 3 - 30, w//2 + 40, h), "platform_broken_1", max_size=(256, 96))
    crop_and_save(img, (w//2 - 30, h * 2 // 3 - 30, w, h), "platform_spring_idle", max_size=(256, 96))
    crop_and_save(img, (w//2 - 30, h * 2 // 3 - 30, w, h), "platform_spring_active", max_size=(256, 96))
    
    p_disp = Image.new("RGBA", (256, 80), (0, 0, 0, 0))
    draw = ImageDraw.Draw(p_disp)
    draw.ellipse([15, 15, 95, 65], fill=(220, 240, 255, 200), outline=(150, 190, 230), width=2)
    draw.ellipse([70, 10, 185, 60], fill=(240, 250, 255, 230), outline=(160, 200, 240), width=2)
    draw.ellipse([160, 15, 240, 65], fill=(220, 240, 255, 200), outline=(150, 190, 230), width=2)
    p_disp.save(os.path.join(SPRITES_DIR, "platform_disappearing.png"))

def process_monsters():
    if not os.path.exists(MONSTERS_IMG):
        return
    img = remove_white_background(Image.open(MONSTERS_IMG))
    w, h = img.size
    
    crop_and_save(img, (0, 0, w//2 + 20, h//2 + 20), "monster_spider", max_size=(200, 200))
    crop_and_save(img, (w//2 - 20, 0, w, h//2 + 20), "monster_bat", max_size=(200, 200))
    crop_and_save(img, (0, h//2 - 20, w//2 + 20, h), "monster_chestnut", max_size=(200, 200))
    crop_and_save(img, (w//2 - 20, h//2 - 20, w, h), "hazard_blackhole", max_size=(200, 200))

def process_powerups():
    if not os.path.exists(POWERUPS_IMG):
        return
    img = remove_white_background(Image.open(POWERUPS_IMG))
    w, h = img.size
    
    crop_and_save(img, (0, 0, w * 35 // 100, h * 35 // 100), "powerup_acorn_gold", max_size=(128, 128))
    crop_and_save(img, (w * 33 // 100, 0, w * 68 // 100, h * 35 // 100), "star_full", max_size=(128, 128))
    crop_and_save(img, (w * 65 // 100, 0, w, h * 42 // 100), "powerup_jetpack", max_size=(128, 128))
    crop_and_save(img, (0, h * 33 // 100, w * 45 // 100, h * 68 // 100), "powerup_propeller", max_size=(128, 128))
    crop_and_save(img, (w * 45 // 100, h * 33 // 100, w * 80 // 100, h * 68 // 100), "powerup_shield", max_size=(128, 128))
    crop_and_save(img, (w * 35 // 100, h * 65 // 100, w * 65 // 100, h), "powerup_spring", max_size=(128, 128))
    crop_and_save(img, (w * 60 // 100, h * 60 // 100, w, h), "bullet_seed", max_size=(64, 64))

def process_ui_and_effects():
    im = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    cx, cy = 64, 64
    points = []
    for i in range(10):
        angle = i * (math.pi / 5) - math.pi / 2
        r = 48 if i % 2 == 0 else 22
        points.append((cx + r * math.cos(angle), cy + r * math.sin(angle)))
    draw.polygon(points, fill=(80, 80, 90, 140), outline=(160, 160, 180), width=3)
    im.save(os.path.join(SPRITES_DIR, "star_empty.png"))
    
    im = Image.new("RGBA", (256, 96), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    draw.polygon([(10, 15), (246, 15), (226, 48), (246, 80), (10, 80), (30, 48)], fill=(220, 50, 45), outline=(130, 20, 15), width=3)
    draw.rectangle([40, 24, 216, 70], fill=(255, 215, 30), outline=(180, 130, 10), width=2)
    for row in range(2):
        for col in range(8):
            color = (255, 255, 255) if (row + col) % 2 == 0 else (30, 30, 30)
            draw.rectangle([48 + col * 20, 30 + row * 18, 48 + (col + 1) * 20, 30 + (row + 1) * 18], fill=color)
    im.save(os.path.join(SPRITES_DIR, "finish_banner.png"))
    
    im = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    draw.ellipse([10, 10, 118, 118], fill=(45, 55, 75), outline=(160, 180, 210), width=4)
    draw.rounded_rectangle([42, 36, 56, 92], radius=4, fill=(255, 255, 255))
    draw.rounded_rectangle([72, 36, 86, 92], radius=4, fill=(255, 255, 255))
    im.save(os.path.join(SPRITES_DIR, "icon_pause.png"))
    
    im = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    draw.ellipse([10, 10, 118, 118], fill=(45, 55, 75), outline=(160, 180, 210), width=4)
    draw.polygon([(30, 48), (48, 48), (68, 30), (68, 98), (48, 80), (30, 80)], fill=(255, 255, 255))
    draw.arc([60, 44, 84, 84], -60, 60, fill=(255, 255, 255), width=4)
    draw.arc([52, 32, 102, 96], -60, 60, fill=(255, 255, 255), width=4)
    im.save(os.path.join(SPRITES_DIR, "icon_sound_on.png"))
    
    im = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    draw.ellipse([10, 10, 118, 118], fill=(45, 55, 75), outline=(160, 180, 210), width=4)
    draw.polygon([(30, 48), (48, 48), (68, 30), (68, 98), (48, 80), (30, 80)], fill=(200, 200, 200))
    draw.line([76, 44, 104, 84], fill=(240, 50, 50), width=5)
    draw.line([104, 44, 76, 84], fill=(240, 50, 50), width=5)
    im.save(os.path.join(SPRITES_DIR, "icon_sound_off.png"))
    
    im = Image.new("RGBA", (256, 256), (18, 30, 42, 255))
    draw = ImageDraw.Draw(im)
    for y in range(256):
        ratio = y / 256.0
        r = int(15 + ratio * 20)
        g = int(35 + ratio * 45)
        b = int(45 + ratio * 30)
        draw.line([(0, y), (256, y)], fill=(r, g, b, 255))
    for cx, cy, sz in [(50, 60, 30), (210, 140, 40), (90, 210, 35), (240, 40, 25)]:
        draw.ellipse([cx - sz, cy - sz//2, cx + sz, cy + sz//2], fill=(255, 255, 255, 8))
    im.save(os.path.join(SPRITES_DIR, "bg_tile.png"))

if __name__ == "__main__":
    print("Extracting and processing sprites...")
    process_app_icon()
    process_characters()
    process_platforms()
    process_monsters()
    process_powerups()
    process_ui_and_effects()
    print("Sprites processing completed!")

import os
import math
from PIL import Image, ImageDraw, ImageFilter

OUTPUT_DIR = "Samples/AcornJump/assets/sprites"
os.makedirs(OUTPUT_DIR, exist_ok=True)

def create_base(size=(256, 256)):
    return Image.new("RGBA", size, (0, 0, 0, 0))

# -------------------------------------------------------------
# 1. ACORN PLAYER SPRITES
# -------------------------------------------------------------

def draw_acorn_body(draw, cx, cy, w, h, body_color=(205, 133, 63), cap_color=(120, 66, 18), eye_type="normal", mouth_type="smile"):
    cap_top = cy - h * 0.55
    cap_bottom = cy - h * 0.1
    cap_left = cx - w * 0.55
    cap_right = cx + w * 0.55
    
    nut_top = cy - h * 0.25
    nut_bottom = cy + h * 0.55
    nut_left = cx - w * 0.48
    nut_right = cx + w * 0.48
    
    draw.pieslice([nut_left, nut_top, nut_right, nut_bottom + h*0.2], 0, 180, fill=body_color, outline=(90, 45, 10), width=4)
    draw.pieslice([nut_left + 10, nut_top + 10, nut_left + w*0.4, nut_bottom - 10], 90, 180, fill=(230, 160, 90, 120))
    
    draw.pieslice([cap_left, cap_top, cap_right, cap_bottom + h*0.2], 180, 360, fill=cap_color, outline=(60, 30, 10), width=4)
    for i in range(-3, 4):
        x_off = i * 16
        draw.line([cx + x_off - 10, cap_bottom - 15, cx + x_off + 10, cap_top + 15], fill=(80, 40, 10), width=2)
        draw.line([cx + x_off + 10, cap_bottom - 15, cx + x_off - 10, cap_top + 15], fill=(80, 40, 10), width=2)
        
    stalk_top = cap_top - 20
    draw.line([cx, cap_top, cx + 5, stalk_top], fill=(70, 35, 10), width=8)
    draw.ellipse([cx + 2, stalk_top - 4, cx + 8, stalk_top + 4], fill=(70, 35, 10))
    
    eye_y = cy + 10
    left_eye_x = cx - 22
    right_eye_x = cx + 22
    
    if eye_type == "normal":
        draw.ellipse([left_eye_x - 10, eye_y - 12, left_eye_x + 10, eye_y + 12], fill=(20, 20, 20))
        draw.ellipse([left_eye_x - 6, eye_y - 8, left_eye_x + 2, eye_y - 2], fill=(255, 255, 255))
        draw.ellipse([right_eye_x - 10, eye_y - 12, right_eye_x + 10, eye_y + 12], fill=(20, 20, 20))
        draw.ellipse([right_eye_x - 6, eye_y - 8, right_eye_x + 2, eye_y - 2], fill=(255, 255, 255))
        draw.ellipse([cx - 42, eye_y + 8, cx - 26, eye_y + 20], fill=(230, 100, 100, 150))
        draw.ellipse([cx + 26, eye_y + 8, cx + 42, eye_y + 20], fill=(230, 100, 100, 150))
    elif eye_type == "wide":
        draw.ellipse([left_eye_x - 14, eye_y - 14, left_eye_x + 14, eye_y + 14], fill=(255, 255, 255), outline=(20, 20, 20), width=3)
        draw.ellipse([left_eye_x - 5, eye_y - 5, left_eye_x + 5, eye_y + 5], fill=(20, 20, 20))
        draw.ellipse([right_eye_x - 14, eye_y - 14, right_eye_x + 14, eye_y + 14], fill=(255, 255, 255), outline=(20, 20, 20), width=3)
        draw.ellipse([right_eye_x - 5, eye_y - 5, right_eye_x + 5, eye_y + 5], fill=(20, 20, 20))
    elif eye_type == "dead":
        for ex in [left_eye_x, right_eye_x]:
            draw.line([ex - 10, eye_y - 10, ex + 10, eye_y + 10], fill=(30, 30, 30), width=4)
            draw.line([ex + 10, eye_y - 10, ex - 10, eye_y + 10], fill=(30, 30, 30), width=4)
            
    if mouth_type == "smile":
        draw.arc([cx - 16, eye_y + 10, cx + 16, eye_y + 30], 0, 180, fill=(30, 30, 30), width=4)
    elif mouth_type == "happy_open":
        draw.chord([cx - 18, eye_y + 8, cx + 18, eye_y + 32], 0, 180, fill=(180, 40, 40), outline=(30, 30, 30), width=3)
        draw.chord([cx - 10, eye_y + 18, cx + 10, eye_y + 32], 0, 180, fill=(240, 100, 100))
    elif mouth_type == "surprised":
        draw.ellipse([cx - 10, eye_y + 14, cx + 10, eye_y + 34], fill=(180, 40, 40), outline=(30, 30, 30), width=3)
    elif mouth_type == "snout":
        draw.polygon([(cx - 12, eye_y + 16), (cx + 12, eye_y + 16), (cx + 8, eye_y - 4), (cx - 8, eye_y - 4)], fill=(160, 90, 30), outline=(40, 20, 10))
        draw.ellipse([cx - 8, eye_y - 8, cx + 8, eye_y], fill=(60, 20, 10))

def gen_acorn_idle():
    im = create_base((256, 256))
    draw = ImageDraw.Draw(im)
    draw_acorn_body(draw, 128, 136, 120, 150, eye_type="normal", mouth_type="smile")
    im.save(os.path.join(OUTPUT_DIR, "acorn_idle.png"))

def gen_acorn_jump():
    im = create_base((256, 256))
    draw = ImageDraw.Draw(im)
    draw_acorn_body(draw, 128, 128, 108, 165, eye_type="normal", mouth_type="happy_open")
    draw.ellipse([100, 220, 118, 235], fill=(140, 80, 30), outline=(60, 30, 10), width=2)
    draw.ellipse([138, 220, 156, 235], fill=(140, 80, 30), outline=(60, 30, 10), width=2)
    im.save(os.path.join(OUTPUT_DIR, "acorn_jump.png"))

def gen_acorn_fall():
    im = create_base((256, 256))
    draw = ImageDraw.Draw(im)
    draw_acorn_body(draw, 128, 136, 125, 145, eye_type="wide", mouth_type="surprised")
    im.save(os.path.join(OUTPUT_DIR, "acorn_fall.png"))

def gen_acorn_shoot():
    im = create_base((256, 256))
    draw = ImageDraw.Draw(im)
    draw_acorn_body(draw, 128, 138, 120, 150, eye_type="wide", mouth_type="snout")
    draw.polygon([(128, 30), (136, 45), (150, 48), (138, 56), (142, 70), (128, 60), (114, 70), (118, 56), (106, 48), (120, 45)], fill=(255, 230, 80))
    im.save(os.path.join(OUTPUT_DIR, "acorn_shoot.png"))

def gen_acorn_propeller():
    im = create_base((256, 256))
    draw = ImageDraw.Draw(im)
    draw_acorn_body(draw, 128, 142, 115, 145, eye_type="normal", mouth_type="happy_open")
    draw.ellipse([70, 30, 186, 46], fill=(255, 220, 40), outline=(200, 150, 20), width=3)
    draw.ellipse([122, 28, 134, 48], fill=(220, 50, 50))
    draw.arc([60, 24, 196, 52], 10, 170, fill=(255, 255, 255, 180), width=2)
    im.save(os.path.join(OUTPUT_DIR, "acorn_propeller.png"))

def gen_acorn_jetpack():
    im = create_base((256, 256))
    draw = ImageDraw.Draw(im)
    draw.rounded_rectangle([45, 90, 85, 190], radius=15, fill=(220, 60, 50), outline=(120, 20, 20), width=3)
    draw.polygon([(50, 190), (80, 190), (85, 205), (45, 205)], fill=(80, 80, 80))
    draw.rounded_rectangle([171, 90, 211, 190], radius=15, fill=(220, 60, 50), outline=(120, 20, 20), width=3)
    draw.polygon([(176, 190), (206, 190), (211, 205), (171, 205)], fill=(80, 80, 80))
    draw.polygon([(48, 205), (82, 205), (65, 248)], fill=(60, 180, 255))
    draw.polygon([(54, 205), (76, 205), (65, 235)], fill=(255, 255, 255))
    draw.polygon([(174, 205), (208, 205), (191, 248)], fill=(60, 180, 255))
    draw.polygon([(180, 205), (202, 205), (191, 235)], fill=(255, 255, 255))
    draw_acorn_body(draw, 128, 130, 115, 150, eye_type="normal", mouth_type="happy_open")
    im.save(os.path.join(OUTPUT_DIR, "acorn_jetpack.png"))

def gen_acorn_dead():
    im = create_base((256, 256))
    draw = ImageDraw.Draw(im)
    draw_acorn_body(draw, 128, 136, 120, 150, eye_type="dead", mouth_type="surprised")
    im.save(os.path.join(OUTPUT_DIR, "acorn_dead.png"))

# -------------------------------------------------------------
# 2. PLATFORMS (256 x 80)
# -------------------------------------------------------------

def gen_platform_wood():
    im = create_base((256, 80))
    draw = ImageDraw.Draw(im)
    draw.rounded_rectangle([10, 20, 246, 60], radius=16, fill=(150, 95, 45), outline=(75, 45, 18), width=4)
    draw.line([25, 30, 230, 30], fill=(185, 125, 65), width=3)
    draw.line([40, 42, 215, 42], fill=(120, 75, 30), width=3)
    draw.line([30, 50, 220, 50], fill=(110, 65, 25), width=2)
    draw.ellipse([70, 35, 86, 47], fill=(110, 65, 25))
    draw.ellipse([74, 38, 82, 44], fill=(150, 95, 45))
    im.save(os.path.join(OUTPUT_DIR, "platform_wood.png"))

def gen_platform_leaf():
    im = create_base((256, 80))
    draw = ImageDraw.Draw(im)
    draw.rounded_rectangle([10, 20, 246, 60], radius=16, fill=(130, 85, 40), outline=(65, 40, 15), width=3)
    draw.ellipse([15, 12, 85, 38], fill=(70, 175, 45), outline=(35, 110, 25), width=2)
    draw.ellipse([75, 8, 155, 35], fill=(85, 195, 55), outline=(40, 120, 30), width=2)
    draw.ellipse([145, 10, 215, 36], fill=(70, 175, 45), outline=(35, 110, 25), width=2)
    draw.ellipse([195, 14, 245, 38], fill=(95, 210, 65), outline=(45, 130, 35), width=2)
    draw.line([30, 25, 70, 25], fill=(130, 230, 90), width=2)
    draw.line([95, 20, 135, 20], fill=(140, 240, 100), width=2)
    draw.line([160, 22, 200, 22], fill=(130, 230, 90), width=2)
    im.save(os.path.join(OUTPUT_DIR, "platform_leaf.png"))

def gen_platform_moving():
    im = create_base((256, 80))
    draw = ImageDraw.Draw(im)
    draw.rounded_rectangle([10, 20, 246, 60], radius=16, fill=(80, 180, 230), outline=(30, 100, 160), width=4)
    draw.rounded_rectangle([18, 25, 238, 40], radius=8, fill=(180, 235, 255, 220))
    for cx in [50, 128, 200]:
        draw.polygon([(cx, 32), (cx + 5, 40), (cx, 48), (cx - 5, 40)], fill=(255, 255, 255))
    im.save(os.path.join(OUTPUT_DIR, "platform_moving.png"))

def gen_platform_broken_1():
    im = create_base((256, 80))
    draw = ImageDraw.Draw(im)
    draw.rounded_rectangle([10, 20, 246, 60], radius=16, fill=(125, 80, 40), outline=(60, 35, 15), width=4)
    draw.line([(120, 20), (125, 35), (118, 48), (128, 60)], fill=(30, 15, 5), width=4)
    draw.line([(125, 35), (135, 42)], fill=(30, 15, 5), width=3)
    im.save(os.path.join(OUTPUT_DIR, "platform_broken_1.png"))

def gen_platform_broken_2():
    im = create_base((256, 80))
    draw = ImageDraw.Draw(im)
    draw.polygon([(10, 30), (110, 22), (105, 58), (10, 70)], fill=(115, 70, 35), outline=(50, 25, 10), width=3)
    draw.polygon([(145, 22), (246, 30), (246, 70), (150, 58)], fill=(115, 70, 35), outline=(50, 25, 10), width=3)
    im.save(os.path.join(OUTPUT_DIR, "platform_broken_2.png"))

def gen_platform_disappearing():
    im = create_base((256, 80))
    draw = ImageDraw.Draw(im)
    draw.ellipse([15, 15, 95, 65], fill=(220, 240, 255, 200), outline=(150, 190, 230), width=2)
    draw.ellipse([70, 10, 185, 60], fill=(240, 250, 255, 230), outline=(160, 200, 240), width=2)
    draw.ellipse([160, 15, 240, 65], fill=(220, 240, 255, 200), outline=(150, 190, 230), width=2)
    for sx, sy in [(50, 35), (128, 25), (200, 40)]:
        draw.polygon([(sx, sy-6), (sx+2, sy-2), (sx+6, sy), (sx+2, sy+2), (sx, sy+6), (sx-2, sy+2), (sx-6, sy), (sx-2, sy-2)], fill=(255, 255, 180))
    im.save(os.path.join(OUTPUT_DIR, "platform_disappearing.png"))

def gen_platform_spring_idle():
    im = create_base((256, 80))
    draw = ImageDraw.Draw(im)
    draw.rounded_rectangle([10, 35, 246, 70], radius=14, fill=(150, 95, 45), outline=(75, 45, 18), width=3)
    sx = 128
    draw.ellipse([sx - 20, 8, sx + 20, 22], fill=(230, 40, 40), outline=(140, 15, 15), width=2)
    draw.ellipse([sx - 18, 16, sx + 18, 28], fill=(210, 30, 30), outline=(140, 15, 15), width=2)
    draw.ellipse([sx - 16, 24, sx + 16, 36], fill=(190, 20, 20), outline=(140, 15, 15), width=2)
    im.save(os.path.join(OUTPUT_DIR, "platform_spring_idle.png"))

def gen_platform_spring_active():
    im = create_base((256, 80))
    draw = ImageDraw.Draw(im)
    draw.rounded_rectangle([10, 45, 246, 75], radius=12, fill=(150, 95, 45), outline=(75, 45, 18), width=3)
    sx = 128
    draw.ellipse([sx - 24, 0, sx + 24, 14], fill=(255, 60, 60), outline=(160, 20, 20), width=2)
    draw.line([(sx - 18, 12), (sx + 18, 22), (sx - 18, 32), (sx + 18, 42), (sx, 48)], fill=(220, 40, 40), width=6)
    im.save(os.path.join(OUTPUT_DIR, "platform_spring_active.png"))

# -------------------------------------------------------------
# 3. HAZARDS & MONSTERS (256 x 256)
# -------------------------------------------------------------

def gen_monster_spider():
    im = create_base((256, 256))
    draw = ImageDraw.Draw(im)
    cx, cy = 128, 130
    
    leg_coords = [
        [(-30, -10), (-70, -40), (-100, -20)],
        [(-35, 0), (-85, -10), (-110, 20)],
        [(-35, 15), (-80, 30), (-105, 65)],
        [(-25, 25), (-65, 60), (-85, 95)],
        [(30, -10), (70, -40), (100, -20)],
        [(35, 0), (85, -10), (110, 20)],
        [(35, 15), (80, 30), (105, 65)],
        [(25, 25), (65, 60), (85, 95)],
    ]
    for leg in leg_coords:
        p0 = (cx + leg[0][0], cy + leg[0][1])
        p1 = (cx + leg[1][0], cy + leg[1][1])
        p2 = (cx + leg[2][0], cy + leg[2][1])
        draw.line([p0, p1, p2], fill=(60, 20, 80), width=6)
    
    draw.ellipse([cx - 55, cy - 50, cx + 55, cy + 55], fill=(130, 40, 160), outline=(60, 15, 80), width=4)
    draw.ellipse([cx - 38, cy - 25, cx + 38, cy + 45], fill=(100, 25, 130), outline=(50, 10, 70), width=3)
    
    draw.ellipse([cx - 26, cy - 8, cx - 10, cy + 8], fill=(255, 230, 40), outline=(100, 10, 10), width=2)
    draw.ellipse([cx + 10, cy - 8, cx + 26, cy + 8], fill=(255, 230, 40), outline=(100, 10, 10), width=2)
    draw.ellipse([cx - 20, cy + 8, cx - 8, cy + 20], fill=(255, 80, 40), outline=(80, 0, 0), width=1)
    draw.ellipse([cx + 8, cy + 8, cx + 20, cy + 20], fill=(255, 80, 40), outline=(80, 0, 0), width=1)
    
    draw.polygon([(cx - 14, cy + 35), (cx - 6, cy + 35), (cx - 10, cy + 50)], fill=(255, 255, 255), outline=(50, 0, 0))
    draw.polygon([(cx + 6, cy + 35), (cx + 14, cy + 35), (cx + 10, cy + 50)], fill=(255, 255, 255), outline=(50, 0, 0))
    im.save(os.path.join(OUTPUT_DIR, "monster_spider.png"))

def gen_monster_bat():
    im = create_base((256, 256))
    draw = ImageDraw.Draw(im)
    cx, cy = 128, 130
    draw.polygon([(cx - 30, cy), (cx - 90, cy - 50), (cx - 120, cy - 20), (cx - 100, cy + 30), (cx - 70, cy + 20), (cx - 40, cy + 35)], fill=(65, 45, 95), outline=(30, 20, 50), width=3)
    draw.polygon([(cx + 30, cy), (cx + 90, cy - 50), (cx + 120, cy - 20), (cx + 100, cy + 30), (cx + 70, cy + 20), (cx + 40, cy + 35)], fill=(65, 45, 95), outline=(30, 20, 50), width=3)
    draw.ellipse([cx - 35, cy - 35, cx + 35, cy + 45], fill=(95, 65, 130), outline=(45, 25, 70), width=3)
    draw.polygon([(cx - 28, cy - 30), (cx - 24, cy - 65), (cx - 8, cy - 35)], fill=(120, 80, 160), outline=(45, 25, 70), width=2)
    draw.polygon([(cx + 8, cy - 35), (cx + 24, cy - 65), (cx + 28, cy - 30)], fill=(120, 80, 160), outline=(45, 25, 70), width=2)
    draw.ellipse([cx - 20, cy - 10, cx - 6, cy + 4], fill=(255, 40, 40))
    draw.ellipse([cx + 6, cy - 10, cx + 20, cy + 4], fill=(255, 40, 40))
    draw.arc([cx - 12, cy + 10, cx + 12, cy + 24], 0, 180, fill=(30, 10, 30), width=3)
    draw.polygon([(cx - 8, cy + 16), (cx - 4, cy + 16), (cx - 6, cy + 24)], fill=(255, 255, 255))
    draw.polygon([(cx + 4, cy + 16), (cx + 8, cy + 16), (cx + 6, cy + 24)], fill=(255, 255, 255))
    im.save(os.path.join(OUTPUT_DIR, "monster_bat.png"))

def gen_monster_chestnut():
    im = create_base((256, 256))
    draw = ImageDraw.Draw(im)
    cx, cy = 128, 128
    num_spikes = 16
    for i in range(num_spikes):
        angle = i * (2 * math.pi / num_spikes)
        r_inner = 55
        r_outer = 95
        p_tip = (cx + r_outer * math.cos(angle), cy + r_outer * math.sin(angle))
        p_l = (cx + r_inner * math.cos(angle - 0.15), cy + r_inner * math.sin(angle - 0.15))
        p_r = (cx + r_inner * math.cos(angle + 0.15), cy + r_inner * math.sin(angle + 0.15))
        draw.polygon([p_l, p_tip, p_r], fill=(180, 110, 40), outline=(90, 50, 15), width=2)
    draw.ellipse([cx - 60, cy - 60, cx + 60, cy + 60], fill=(130, 75, 30), outline=(70, 35, 10), width=4)
    draw.polygon([(cx - 36, cy - 20), (cx - 8, cy - 10), (cx - 16, cy + 5), (cx - 38, cy - 5)], fill=(255, 220, 30), outline=(40, 10, 0), width=2)
    draw.polygon([(cx + 8, cy - 10), (cx + 36, cy - 20), (cx + 38, cy - 5), (cx + 16, cy + 5)], fill=(255, 220, 30), outline=(40, 10, 0), width=2)
    draw.ellipse([cx - 24, cy - 12, cx - 16, cy - 4], fill=(200, 20, 20))
    draw.ellipse([cx + 16, cy - 12, cx + 24, cy - 4], fill=(200, 20, 20))
    im.save(os.path.join(OUTPUT_DIR, "monster_chestnut.png"))

def gen_hazard_blackhole():
    im = create_base((256, 256))
    draw = ImageDraw.Draw(im)
    cx, cy = 128, 128
    for i in range(8):
        start_angle = i * 45
        draw.arc([20, 20, 236, 236], start_angle, start_angle + 60, fill=(160, 60, 240, 160), width=5)
        draw.arc([40, 40, 216, 216], start_angle + 20, start_angle + 90, fill=(210, 100, 255, 200), width=6)
    draw.ellipse([cx - 50, cy - 50, cx + 50, cy + 50], fill=(15, 5, 25), outline=(180, 50, 255), width=6)
    draw.ellipse([cx - 40, cy - 40, cx + 40, cy + 40], fill=(5, 0, 10))
    im.save(os.path.join(OUTPUT_DIR, "hazard_blackhole.png"))

# -------------------------------------------------------------
# 4. COLLECTIBLES & POWERUPS (128 x 128)
# -------------------------------------------------------------

def gen_powerup_spring():
    im = create_base((128, 128))
    draw = ImageDraw.Draw(im)
    cx, cy = 64, 64
    draw.ellipse([cx - 24, cy - 35, cx + 24, cy - 15], fill=(255, 60, 60), outline=(150, 20, 20), width=3)
    draw.ellipse([cx - 22, cy - 20, cx + 22, cy], fill=(235, 45, 45), outline=(150, 20, 20), width=3)
    draw.ellipse([cx - 20, cy - 5, cx + 20, cy + 15], fill=(215, 30, 30), outline=(150, 20, 20), width=3)
    draw.ellipse([cx - 22, cy + 10, cx + 22, cy + 30], fill=(195, 20, 20), outline=(150, 20, 20), width=3)
    im.save(os.path.join(OUTPUT_DIR, "powerup_spring.png"))

def gen_powerup_propeller():
    im = create_base((128, 128))
    draw = ImageDraw.Draw(im)
    cx, cy = 64, 64
    draw.pieslice([cx - 30, cy - 10, cx + 30, cy + 45], 180, 360, fill=(60, 140, 240), outline=(20, 60, 140), width=3)
    draw.line([cx, cy - 10, cx, cy - 25], fill=(180, 180, 180), width=4)
    draw.ellipse([cx - 45, cy - 35, cx + 45, cy - 20], fill=(255, 220, 40), outline=(180, 140, 20), width=2)
    draw.ellipse([cx - 8, cy - 32, cx + 8, cy - 22], fill=(220, 40, 40))
    im.save(os.path.join(OUTPUT_DIR, "powerup_propeller.png"))

def gen_powerup_jetpack():
    im = create_base((128, 128))
    draw = ImageDraw.Draw(im)
    cx, cy = 64, 60
    draw.rounded_rectangle([cx - 36, cy - 35, cx - 8, cy + 35], radius=10, fill=(235, 55, 45), outline=(130, 20, 15), width=3)
    draw.rounded_rectangle([cx + 8, cy - 35, cx + 36, cy + 35], radius=10, fill=(235, 55, 45), outline=(130, 20, 15), width=3)
    draw.rectangle([cx - 10, cy - 10, cx + 10, cy + 10], fill=(60, 60, 60))
    draw.polygon([(cx - 32, cy + 35), (cx - 12, cy + 35), (cx - 8, cy + 48), (cx - 36, cy + 48)], fill=(100, 100, 100))
    draw.polygon([(cx + 12, cy + 35), (cx + 32, cy + 35), (cx + 36, cy + 48), (cx + 8, cy + 48)], fill=(100, 100, 100))
    im.save(os.path.join(OUTPUT_DIR, "powerup_jetpack.png"))

def gen_powerup_shield():
    im = create_base((128, 128))
    draw = ImageDraw.Draw(im)
    cx, cy = 64, 64
    draw.ellipse([cx - 45, cy - 45, cx + 45, cy + 45], fill=(80, 210, 255, 140), outline=(140, 240, 255), width=4)
    draw.ellipse([cx - 32, cy - 38, cx + 5, cy - 10], fill=(255, 255, 255, 180))
    im.save(os.path.join(OUTPUT_DIR, "powerup_shield.png"))

def gen_powerup_acorn_gold():
    im = create_base((128, 128))
    draw = ImageDraw.Draw(im)
    cx, cy = 64, 68
    draw_acorn_body(draw, cx, cy, 60, 75, body_color=(255, 205, 30), cap_color=(220, 150, 15), eye_type="normal", mouth_type="smile")
    draw.polygon([(cx + 25, cy - 25), (cx + 30, cy - 15), (cx + 40, cy - 10), (cx + 30, cy - 5), (cx + 25, cy + 5), (cx + 20, cy - 5), (cx + 10, cy - 10), (cx + 20, cy - 15)], fill=(255, 255, 255))
    im.save(os.path.join(OUTPUT_DIR, "powerup_acorn_gold.png"))

def gen_bullet_seed():
    im = create_base((64, 64))
    draw = ImageDraw.Draw(im)
    draw.polygon([(32, 6), (46, 32), (32, 56), (18, 32)], fill=(255, 180, 40), outline=(200, 90, 10), width=2)
    draw.polygon([(32, 12), (40, 32), (32, 48), (24, 32)], fill=(255, 240, 120))
    im.save(os.path.join(OUTPUT_DIR, "bullet_seed.png"))

# -------------------------------------------------------------
# 5. UI, BADGES, AND ICONS (128 x 128)
# -------------------------------------------------------------

def gen_star_full():
    im = create_base((128, 128))
    draw = ImageDraw.Draw(im)
    cx, cy = 64, 64
    points = []
    for i in range(10):
        angle = i * (math.pi / 5) - math.pi / 2
        r = 48 if i % 2 == 0 else 22
        points.append((cx + r * math.cos(angle), cy + r * math.sin(angle)))
    draw.polygon(points, fill=(255, 215, 30), outline=(200, 140, 10), width=3)
    inner_points = []
    for i in range(10):
        angle = i * (math.pi / 5) - math.pi / 2
        r = 36 if i % 2 == 0 else 16
        inner_points.append((cx + r * math.cos(angle), cy + r * math.sin(angle)))
    draw.polygon(inner_points, fill=(255, 240, 100))
    im.save(os.path.join(OUTPUT_DIR, "star_full.png"))

def gen_star_empty():
    im = create_base((128, 128))
    draw = ImageDraw.Draw(im)
    cx, cy = 64, 64
    points = []
    for i in range(10):
        angle = i * (math.pi / 5) - math.pi / 2
        r = 48 if i % 2 == 0 else 22
        points.append((cx + r * math.cos(angle), cy + r * math.sin(angle)))
    draw.polygon(points, fill=(80, 80, 90, 140), outline=(160, 160, 180), width=3)
    im.save(os.path.join(OUTPUT_DIR, "star_empty.png"))

def gen_finish_banner():
    im = create_base((256, 128))
    draw = ImageDraw.Draw(im)
    draw.polygon([(20, 30), (236, 30), (216, 75), (236, 110), (20, 110), (40, 75)], fill=(220, 50, 45), outline=(130, 20, 15), width=4)
    draw.rectangle([45, 42, 211, 98], fill=(255, 215, 30), outline=(180, 130, 10), width=3)
    for row in range(2):
        for col in range(8):
            color = (255, 255, 255) if (row + col) % 2 == 0 else (30, 30, 30)
            draw.rectangle([55 + col * 18, 50 + row * 18, 55 + (col + 1) * 18, 50 + (row + 1) * 18], fill=color)
    im.save(os.path.join(OUTPUT_DIR, "finish_banner.png"))

def gen_icon_pause():
    im = create_base((128, 128))
    draw = ImageDraw.Draw(im)
    draw.ellipse([10, 10, 118, 118], fill=(45, 55, 75), outline=(160, 180, 210), width=4)
    draw.rounded_rectangle([42, 36, 56, 92], radius=4, fill=(255, 255, 255))
    draw.rounded_rectangle([72, 36, 86, 92], radius=4, fill=(255, 255, 255))
    im.save(os.path.join(OUTPUT_DIR, "icon_pause.png"))

def gen_icon_sound_on():
    im = create_base((128, 128))
    draw = ImageDraw.Draw(im)
    draw.ellipse([10, 10, 118, 118], fill=(45, 55, 75), outline=(160, 180, 210), width=4)
    draw.polygon([(30, 48), (48, 48), (68, 30), (68, 98), (48, 80), (30, 80)], fill=(255, 255, 255))
    draw.arc([60, 44, 84, 84], -60, 60, fill=(255, 255, 255), width=4)
    draw.arc([52, 32, 102, 96], -60, 60, fill=(255, 255, 255), width=4)
    im.save(os.path.join(OUTPUT_DIR, "icon_sound_on.png"))

def gen_icon_sound_off():
    im = create_base((128, 128))
    draw = ImageDraw.Draw(im)
    draw.ellipse([10, 10, 118, 118], fill=(45, 55, 75), outline=(160, 180, 210), width=4)
    draw.polygon([(30, 48), (48, 48), (68, 30), (68, 98), (48, 80), (30, 80)], fill=(200, 200, 200))
    draw.line([76, 44, 104, 84], fill=(240, 50, 50), width=5)
    draw.line([104, 44, 76, 84], fill=(240, 50, 50), width=5)
    im.save(os.path.join(OUTPUT_DIR, "icon_sound_off.png"))

def gen_bg_tile():
    im = Image.new("RGBA", (512, 512), (18, 30, 42, 255))
    draw = ImageDraw.Draw(im)
    for y in range(512):
        ratio = y / 512.0
        r = int(15 + ratio * 20)
        g = int(35 + ratio * 45)
        b = int(45 + ratio * 30)
        draw.line([(0, y), (512, y)], fill=(r, g, b, 255))
    for cx, cy, sz in [(100, 120, 60), (420, 280, 80), (180, 420, 70), (480, 80, 50)]:
        draw.ellipse([cx - sz, cy - sz//2, cx + sz, cy + sz//2], fill=(255, 255, 255, 8))
    im.save(os.path.join(OUTPUT_DIR, "bg_tile.png"))

def gen_app_icon():
    icon_dir = "Samples/AcornJump/AcornJump/Assets.xcassets/AppIcon.appiconset"
    os.makedirs(icon_dir, exist_ok=True)
    im = Image.new("RGBA", (1024, 1024), (24, 48, 64, 255))
    draw = ImageDraw.Draw(im)
    
    for y in range(1024):
        ratio = y / 1024.0
        r = int(30 + ratio * 40)
        g = int(90 + ratio * 70)
        b = int(140 - ratio * 40)
        draw.line([(0, y), (1024, y)], fill=(r, g, b, 255))
    
    draw.rounded_rectangle([180, 750, 844, 850], radius=40, fill=(150, 95, 45), outline=(75, 45, 18), width=10)
    draw.ellipse([450, 670, 574, 750], fill=(240, 50, 50), outline=(150, 20, 20), width=8)
    
    draw_acorn_body(draw, 512, 440, 360, 480, eye_type="normal", mouth_type="happy_open")
    
    draw.ellipse([260, 120, 764, 180], fill=(255, 220, 40), outline=(190, 140, 20), width=8)
    draw.ellipse([480, 110, 544, 190], fill=(230, 40, 40))
    
    for sx, sy in [(200, 220), (840, 300), (300, 620), (780, 580)]:
        points = []
        for i in range(10):
            angle = i * (math.pi / 5) - math.pi / 2
            r = 32 if i % 2 == 0 else 14
            points.append((sx + r * math.cos(angle), sy + r * math.sin(angle)))
        draw.polygon(points, fill=(255, 230, 50), outline=(210, 160, 20), width=3)
    
    im.save(os.path.join(icon_dir, "AppIcon-1024x1024.png"))
    print("Generated AppIcon-1024x1024.png")

if __name__ == "__main__":
    print("Generating Acorn Jump sprites...")
    gen_acorn_idle()
    gen_acorn_jump()
    gen_acorn_fall()
    gen_acorn_shoot()
    gen_acorn_propeller()
    gen_acorn_jetpack()
    gen_acorn_dead()
    
    gen_platform_wood()
    gen_platform_leaf()
    gen_platform_moving()
    gen_platform_broken_1()
    gen_platform_broken_2()
    gen_platform_disappearing()
    gen_platform_spring_idle()
    gen_platform_spring_active()
    
    gen_monster_spider()
    gen_monster_bat()
    gen_monster_chestnut()
    gen_hazard_blackhole()
    
    gen_powerup_spring()
    gen_powerup_propeller()
    gen_powerup_jetpack()
    gen_powerup_shield()
    gen_powerup_acorn_gold()
    gen_bullet_seed()
    
    gen_star_full()
    gen_star_empty()
    gen_finish_banner()
    gen_icon_pause()
    gen_icon_sound_on()
    gen_icon_sound_off()
    gen_bg_tile()
    
    gen_app_icon()
    print("All sprites generated successfully!")

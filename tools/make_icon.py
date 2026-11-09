from PIL import Image, ImageDraw, ImageFilter

S = 1024
TOP = (10, 132, 255)
BOTTOM = (94, 92, 230)

# 垂直渐变背景
img = Image.new("RGB", (S, S), TOP)
draw = ImageDraw.Draw(img)
for y in range(S):
    t = y / (S - 1)
    color = (
        int(TOP[0] + (BOTTOM[0] - TOP[0]) * t),
        int(TOP[1] + (BOTTOM[1] - TOP[1]) * t),
        int(TOP[2] + (BOTTOM[2] - TOP[2]) * t),
    )
    draw.line([(0, y), (S, y)], fill=color)

# 柔光：左上角高光
glow = Image.new("L", (S, S), 0)
gdraw = ImageDraw.Draw(glow)
gdraw.ellipse([-S * 0.35, -S * 0.45, S * 0.75, S * 0.55], fill=70)
glow = glow.filter(ImageFilter.GaussianBlur(S * 0.12))
img = Image.composite(Image.new("RGB", (S, S), (255, 255, 255)), img, glow.point(lambda v: int(v * 0.55)))

draw = ImageDraw.Draw(img, "RGBA")

# 播放器窗口（白色半透明圆角矩形）
pad = 176
box = [pad, pad + 40, S - pad, S - pad - 40]
draw.rounded_rectangle(box, radius=118, fill=(255, 255, 255, 240))

# 窗口顶部标题栏
bar_h = 96
draw.rounded_rectangle(
    [box[0], box[1], box[2], box[1] + bar_h * 2],
    radius=118,
    fill=(255, 255, 255, 240),
)
draw.rectangle([box[0], box[1] + bar_h, box[2], box[1] + bar_h * 1.2], fill=(10, 132, 255, 40))

cx = S // 2
# 三个小圆点（窗口控件）
for i, x in enumerate([box[0] + 46, box[0] + 96, box[0] + 146]):
    draw.ellipse([x - 11, box[1] + 40, x + 11, box[1] + 62], fill=(10, 132, 255, 200))

# 播放三角
tri_h = 210
tri_w = 186
tcy = (box[1] + box[3]) // 2 + 6
triangle = [
    (cx - tri_w // 2 + 22, tcy - tri_h // 2),
    (cx - tri_w // 2 + 22, tcy + tri_h // 2),
    (cx - tri_w // 2 + 22 + tri_w, tcy),
]
draw.polygon(triangle, fill=(10, 132, 255, 255))

# 右下角三个分段条（暗示 m3u8 分片）
bar_y = box[3] - 96
for i in range(3):
    x0 = box[0] + 54 + i * 74
    w = 56 if i < 2 else 34
    draw.rounded_rectangle([x0, bar_y, x0 + w, bar_y + 22], radius=11, fill=(10, 132, 255, 120 + i * 45))

# 右侧无线波（嗅探）
def arc(cx0, cy0, r, width, alpha, start=300, end=60):
    draw.arc([cx0 - r, cy0 - r, cx0 + r, cy0 + r], start=start, end=end, fill=(10, 132, 255, alpha), width=width)

wx = box[2] - 110
wy = tcy + 6
arc(wx, wy, 78, 14, 255)
arc(wx, wy, 124, 12, 170)

img = img.convert("RGB")
img.save(r"D:\Tools\Project m3u8\Sources\App\Assets.xcassets\AppIcon.appiconset\Icon-1024.png", "PNG")
print("icon written")

from PIL import Image, ImageDraw
import os

out_path = os.path.join(os.path.dirname(__file__), "AppIcon.ico")
img = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Blue rounded square background
background = (0, 120, 215, 255)
draw.rounded_rectangle((18, 18, 238, 238), radius=42, fill=background)

# White note glyph
white = (255, 255, 255, 255)
draw.rounded_rectangle((58, 64, 198, 194), radius=18, fill=white)

draw.rectangle((90, 92, 166, 102), fill=background)
draw.rectangle((90, 118, 164, 126), fill=background)
draw.rectangle((90, 134, 156, 142), fill=background)

img.save(out_path, format="ICO")
print(f"Created {out_path}")

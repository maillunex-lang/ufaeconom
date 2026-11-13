extends RefCounted
## BUSINESS EMPIRE ONLINE: original procedural 2.5D buildings.
## Appearance only; no local ownership, production or construction decisions.
const COLORS := {
    "Жилой дом": Color("#d5c9b5"),
    "Магазин": Color("#719fa9"),
    "Завод": Color("#87939b"),
    "Склад": Color("#b6a48b"),
    "Офис": Color("#819eae"),
    "НИИ": Color("#99a6b3"),
    "Автосалон": Color("#b8a88d"),
    "Шахта": Color("#867e75"),
}
static func palette(kind: String, district: int) -> Color:
    var c: Color = COLORS.get(kind, Color("#a6b6ac"))
    if district == 1:
        return c.lerp(Color("#b0c0c2"), 0.23)
    if district == 2:
        return c.lerp(Color("#d9c0a3"), 0.22)
    return c

static func draw(canvas: Node2D, pos: Vector2, kind: String, level: int = 1, building: bool = false, district: int = 0) -> void:
    var shade := palette(kind, district)
    var floor_count: int = 1 if kind in ["Склад","Автосалон","Магазин","Шахта"] else 2
    floor_count += maxi(0, level - 1)
    var height := float(22 + 13 * floor_count)
    var spread := 23.0 if kind not in ["Склад","Автосалон"] else 28.0
    var left := pos + Vector2(-spread,-12)
    var front := pos + Vector2(0,4)
    var right := pos + Vector2(spread,-12)
    var rise := Vector2(0,-height)
    canvas.draw_colored_polygon(PackedVector2Array([left,front,front+rise,left+rise]),shade.darkened(0.31))
    canvas.draw_colored_polygon(PackedVector2Array([front,right,right+rise,front+rise]),shade.darkened(0.15))
    canvas.draw_colored_polygon(PackedVector2Array([left+rise,front+rise,right+rise,pos+Vector2(0,-height-27)]),shade.lightened(0.16))
    # Roof parapet and edge highlight reinforce depth without textures or shaders.
    canvas.draw_line(left+rise, pos+Vector2(0,-height-27), shade.lightened(0.39), 1.2)
    canvas.draw_line(pos+Vector2(0,-height-27), right+rise, shade.darkened(0.13), 1.2)
    canvas.draw_line(front, front+rise, Color("#dce6e2"), 1.1)
    if kind in ["Офис", "НИИ", "Жилой дом"]:
        canvas.draw_rect(Rect2(pos + Vector2(-9,-height-14), Vector2(14,4)), Color("#647982"))
    if kind in ["Завод", "Склад"]:
        for seam in range(2):
            var yy := -height + 13.0 + seam * 12.0
            canvas.draw_line(pos+Vector2(4,yy),pos+Vector2(19,yy+2),shade.lightened(0.23),1.0)
    # Floor glazing: stripes remain visible at small Android screen sizes.
    if kind in ["Офис","НИИ","Жилой дом"]:
        for floor in range(floor_count):
            var yy := -height + 11.0 + float(floor) * 12.0
            canvas.draw_rect(Rect2(pos + Vector2(-18,yy),Vector2(8,6)),Color("#b8d0d7"))
            canvas.draw_rect(Rect2(pos + Vector2(4,yy),Vector2(8,6)),Color("#85aebc"))
            canvas.draw_line(pos + Vector2(-14,yy),pos + Vector2(-14,yy+6),Color("#506e7a"),1.0)
            canvas.draw_line(pos + Vector2(8,yy),pos + Vector2(8,yy+6),Color("#506e7a"),1.0)
    if kind in ["Магазин","Автосалон"]:
        canvas.draw_colored_polygon(PackedVector2Array([
            pos+Vector2(-23,-height+23), pos+Vector2(0,-height+28),
            pos+Vector2(0,-height+35), pos+Vector2(-23,-height+29)
        ]),Color("#f0b369"))
        canvas.draw_rect(Rect2(pos + Vector2(8,-height+25),Vector2(11,12)),Color("#2e738b"))
    if kind == "Завод":
        canvas.draw_rect(Rect2(pos+Vector2(-18,-height-37),Vector2(8,31)),Color("#778393"))
        canvas.draw_rect(Rect2(pos+Vector2(-18,-height-37),Vector2(8,5)),Color("#d0a36e"))
        canvas.draw_rect(Rect2(pos+Vector2(3,-height-18),Vector2(16,5)),Color("#566b7a"))
    elif kind == "Склад":
        canvas.draw_rect(Rect2(pos+Vector2(0,-height+15),Vector2(18,20)),Color("#5f8292"))
        for x in range(3):
            canvas.draw_line(pos+Vector2(0,-height+20+x*5),pos+Vector2(17,-height+20+x*5),Color("#b8c6cb"),1.0)
    elif kind == "НИИ":
        canvas.draw_circle(pos+Vector2(0,-height-23),6.0,Color("#eed88c"))
        canvas.draw_circle(pos+Vector2(0,-height-23),2.0,Color("#719eaa"))
    elif kind == "Шахта":
        canvas.draw_line(pos+Vector2(-10,-height-25),pos+Vector2(10,-height-25),Color("#575a5a"),3.0)
    if level >= 2 and not building:
        # Upgrade roof panels; extra details are cosmetic only.
        canvas.draw_rect(Rect2(pos+Vector2(-9,-height-15),Vector2(18,7)),Color("#4e6675"))
    if level >= 3 and not building:
        canvas.draw_circle(pos+Vector2(13,-height-19),3.3,Color("#edc881"))
    if building:
        # Server says construction is not yet ready: scaffolding/outline.
        var beam := Color("#e2b55d")
        for xx in [-spread,spread]:
            canvas.draw_line(pos+Vector2(xx,-height-4),pos+Vector2(xx,-height-39),beam,2.0)
        canvas.draw_line(pos+Vector2(-spread,-height-31),pos+Vector2(spread,-height-31),beam,2.0)
        canvas.draw_line(pos+Vector2(-spread,-height-22),pos+Vector2(spread,-height-16),beam,1.0)
    if district == 0 and kind == "Жилой дом":
        canvas.draw_circle(pos + Vector2(-29,-2),5.0,Color("#428761"))
import bpy
import json

scene = bpy.context.scene
report = {
    "fps": scene.render.fps,
    "frame_start": scene.frame_start,
    "frame_end": scene.frame_end,
    "objects": [],
    "actions": [],
}
for obj in bpy.data.objects:
    entry = {
        "name": obj.name,
        "type": obj.type,
        "parent": obj.parent.name if obj.parent else "",
    }
    if obj.type == "ARMATURE":
        entry["bones"] = [b.name for b in obj.data.bones]
    anim = obj.animation_data
    if anim:
        entry["action"] = anim.action.name if anim.action else ""
        if anim.action and getattr(anim, "action_slot", None):
            slot = anim.action_slot
            entry["slot"] = getattr(slot, "identifier", "") or str(slot)
        entry["nla"] = [t.name for t in anim.nla_tracks]
    report["objects"].append(entry)
for action in bpy.data.actions:
    slots = []
    if hasattr(action, "slots"):
        for slot in action.slots:
            slots.append({
                "id": getattr(slot, "identifier", ""),
                "target": str(getattr(slot, "target_id_type", "")),
            })
    report["actions"].append({
        "name": action.name,
        "frames": [float(action.frame_range[0]), float(action.frame_range[1])],
        "slots": slots,
    })
path = r"H:\oathbound-game\output\bagyo\idle_inspect.json"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(report, handle, indent=2)
print("WROTE", path)

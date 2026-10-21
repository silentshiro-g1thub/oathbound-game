"""Pack the refined Bagyo clips into one GLB Godot can play on every peer."""

import bpy
import json
import os
from mathutils import Vector

ROOT = r"H:\oathbound-game"
SOURCE = os.path.join(ROOT, "output", "bagyo", "refined_animations")
OUTPUT = os.path.join(ROOT, "assets", "characters", "hunter_bagyo.glb")
MANIFEST = os.path.join(SOURCE, "manifest.json")

ACTORS = ("HunterRig", "Bagyo", "Magazine", "Casing")


def world_bounds():
    low = Vector((1e9, 1e9, 1e9))
    high = Vector((-1e9, -1e9, -1e9))
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            point = obj.matrix_world @ Vector(corner)
            low.x, low.y, low.z = min(low.x, point.x), min(low.y, point.y), min(low.z, point.z)
            high.x, high.y, high.z = max(high.x, point.x), max(high.y, point.y), max(high.z, point.z)
    return low, high


def append_actions(path, names):
    with bpy.data.libraries.load(path, link=False) as (data_from, data_to):
        present = set(data_from.actions)
        wanted = [name for name in names if name in present]
        missing = [name for name in names if name not in present]
        data_to.actions = wanted
    return wanted, missing


def slot_for(action, obj):
    ident = "OB" + obj.name
    for slot in action.slots:
        if getattr(slot, "identifier", "") == ident:
            return slot
    return action.slots[0] if len(action.slots) else None


def add_track(obj, clip_name, action):
    if obj.animation_data is None:
        obj.animation_data_create()
    track = obj.animation_data.nla_tracks.new()
    track.name = clip_name
    start = int(action.frame_range[0])
    strip = track.strips.new(clip_name, start, action)
    slot = slot_for(action, obj)
    if slot is not None and hasattr(strip, "action_slot"):
        strip.action_slot = slot
    return strip


def main():
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(MANIFEST, encoding="utf-8") as handle:
        clips = json.load(handle)

    report = {"appended": {}, "missing": {}, "tracks": []}
    for clip in clips:
        clip_name = clip["animation"]
        if clip_name == "Idle":
            continue
        path = os.path.join(SOURCE, clip["file"])
        names = ["%s_%s" % (clip_name, actor) for actor in ACTORS]
        wanted, missing = append_actions(path, names)
        report["appended"][clip_name] = wanted
        report["missing"][clip_name] = missing

    for clip in clips:
        clip_name = clip["animation"]
        for actor in ACTORS:
            action_name = "%s_%s" % (clip_name, actor)
            action = bpy.data.actions.get(action_name)
            obj = bpy.data.objects.get(actor)
            if action is None or obj is None:
                continue
            add_track(obj, clip_name, action)
            report["tracks"].append(action_name)
        obj = bpy.data.objects.get(actor) if False else None

    for obj in bpy.data.objects:
        if obj.animation_data:
            obj.animation_data.action = None

    for camera in list(bpy.data.objects):
        if camera.type == "CAMERA":
            bpy.data.objects.remove(camera, do_unlink=True)

    low, high = world_bounds()
    report["bounds_min"] = [low.x, low.y, low.z]
    report["bounds_max"] = [high.x, high.y, high.z]
    bpy.context.scene.render.fps = 30
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = 60

    export_args = {
        "filepath": OUTPUT,
        "export_format": "GLB",
        "export_cameras": False,
        "export_lights": False,
        "export_animations": True,
        "export_animation_mode": "NLA_TRACKS",
        "export_skins": True,
        "export_yup": True,
        "export_apply": False,
        "export_texcoords": True,
        "export_normals": True,
        "export_materials": "EXPORT",
    }
    props = {prop.identifier for prop in bpy.ops.export_scene.gltf.get_rna_type().properties}
    if "export_nla_strips_merged_animation_name" in props:
        export_args["export_nla_strips_merged_animation_name"] = "Animation"
    if "export_image_format" in props:
        export_args["export_image_format"] = "JPEG"
    if "export_jpeg_quality" in props:
        export_args["export_jpeg_quality"] = 85
    filtered = {key: value for key, value in export_args.items() if key in props or key == "filepath"}
    bpy.ops.export_scene.gltf(**filtered)

    report["bytes"] = os.path.getsize(OUTPUT)
    report_path = os.path.join(ROOT, "output", "bagyo", "hunter_export.json")
    with open(report_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)
    print("EXPORTED", OUTPUT, report["bytes"])


if __name__ == "__main__":
    main()

extends Node
## Lightweight local-only render diagnostics. No networking or file writes.
const MAX_SAMPLES := 120
var samples: Array[Dictionary] = []
var last_draw_us := 0
var max_draw_us := 0

func record_draw(duration_us: int) -> void:
    last_draw_us = maxi(0, duration_us)
    max_draw_us = maxi(max_draw_us, last_draw_us)

func sample(fps: float, visible_chunks: int, active_chunks: int, plots: int, dynamic_nodes: int) -> void:
    var entry := {
        "fps": maxf(0.0, fps),
        "frame_ms": 1000.0 / maxf(fps, 1.0),
        "draw_ms": float(last_draw_us) / 1000.0,
        "visible_chunks": maxi(0, visible_chunks),
        "active_chunks": maxi(0, active_chunks),
        "plots": maxi(0, plots),
        "dynamic_nodes": maxi(0, dynamic_nodes)
    }
    samples.append(entry)
    if samples.size() > MAX_SAMPLES:
        samples.pop_front()

func summary() -> Dictionary:
    if samples.is_empty():
        return {}
    var total_frame := 0.0
    var total_draw := 0.0
    var min_fps := INF
    var sum_fps := 0.0
    var low_fps_samples := 0
    for entry in samples:
        total_frame += entry["frame_ms"]
        total_draw += entry["draw_ms"]
        min_fps = minf(min_fps, entry["fps"])
        sum_fps += entry["fps"]
        if entry["fps"] < 27.0:
            low_fps_samples += 1
    return {
        "samples": samples.size(),
        "avg_frame_ms": total_frame / samples.size(),
        "avg_draw_ms": total_draw / samples.size(),
        "min_fps": min_fps,
        "avg_fps": sum_fps / samples.size(),
        "low_fps_ratio": float(low_fps_samples) / samples.size(),
        "max_draw_ms": float(max_draw_us) / 1000.0,
        "latest": samples.back().duplicate(true)
    }

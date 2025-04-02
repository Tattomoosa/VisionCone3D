<div align="center">
	<br/>
	<br/>
	<img src="addons/tattomoosa.vision_cone_3d/icons/VisionCone3D.svg" width="100"/>
	<br/>
	<h1>
		VisionCone3D
		<br/>
		<sub>
		<sub>
		<sub>
		Simple but configurable 3D vision cone node for <a href="https://godotengine.org/">Godot</a>
		</sub>
		</sub>
		</sub>
		<br/>
		<br/>
		<br/>
	</h1>
	<br/>
	<br/>
	<img src="./readme_images/demo.png" height="140">
	<img src="./readme_images/stress_test.png" height="140">
	<img src="./readme_images/editor_view.png" height="140">
	<br/>
	<br/>
</div>

> Compatible with Godot 4.4 - see 4.3 branch for Godot 4.3 compatible version

Adds VisionCone3D, which tracks whether or not objects within its cone shape can be "seen".
This can be used to let objects in your game "see" multiple objects efficiently.
Default configuration should work for most use-cases out of the box.

## Features

* Edit range/angle of cone via 3D viewport editor gizmo
* Debug visualization to easily diagnose any issues
* Works with complex objects that have many collision shapes
* Configurable vision probe settings allow tuning effectiveness and performance to your use-case
* Ignore some physics bodies (eg the parent body)
* Separate masks for bodies that can be seen and bodies that can only occlude other objects
* Includes general-purpose ConeShape3D

## Installation

Install via the AssetLib tab within Godot by searching for VisionCone3D

## Usage

Add the VisionCone3D node to your scene. Turn on debug draw to see it working. Then you can...

### Connect to the body visible signals

These signals fire when a body is newly visible or newly hidden.

```python
func _ready():
	vision_cone.body_sighted.connect(_on_body_sighted)
	vision_cone.body_hidden.connect(_on_body_hidden)

func _on_body_sighted(body: Node3D):
	print("body sighted: ", body.name)

func _on_body_hidden(body: Node3D):
	print("body hidden: ", body.name)
```

### Poll the currently visible bodies

```python
func _process(): # doesn't need to be during a physics frame
	print("bodies visible: ", vision_cone.get_visible_bodies())
```

## Performance Tuning

### Vision Test Mode

#### Center

Samples only the center point (position) of the CollisionShape. Most efficient, but least effective
as if the center of a shape is obscured it won't be seen.

```python
vision_cone.vision_test_mode = VisionCone3D.VisionTestMode.SAMPLE_CENTER
```

#### Sample Random Vertices

Uses CollisionShape's `get_debug_mesh` to get a mesh representation of the CollisionShape,
then samples random vertex points from that mesh.
Effectiveness determined by the max body count and max probe per shape count

```python
vision_cone.vision_test_mode = VisionCone3D.VisionTestMode.SAMPLE_RANDOM_VERTICES
vision_cone.vision_test_max_body_count = 50 # Bodies probed, per-frame
vision_cone.vision_test_shape_max_probe_count = 5 # Probes per hidden shape
```

### Collision Masks

VisionCone3D has 2 collision masks, one used for bodies that can be seen by the cone and one for an environment,
which can occlude seen bodies but is not itself probed for visibility.

For example, add the level collision layer to `collision_environment_mask` and the player/enemy/object collision layer to the `collision_mask`.
The player/enemy/object can then hide behind the level, but no processing/probing will occur on the level collision geometry itself.

## The Future

This asset is still in development. I have some ideas for further performance tuning options, and I'm open to feedback on the usability and how to improve documentation or workflows.

### 2D Support?

I am open to adding a 2D version of this addon if there is sufficient interest.

See if [VisionCone2D](https://github.com/d-bucur/godot-vision-cone) meets your needs in the meantime. No relation.

## Upgrading

### 0.1.0 -> 0.2.0

v0.2.0 has significant performance improvements. Probably should have waited a few days before publishing. It probably doesn't have any users yet, but just in case...

* Use "Change Type..." on your VisionCone3Ds and select Area3D.
* Use new ConeShape3D for all your cone-y collision needs
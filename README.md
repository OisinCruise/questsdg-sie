# Quest:SDG - Sustainabot Interactive Experiences

**Name:** Oisin Cruise

**Student Number:** C22517166

**Class Group:** TU 856/4 - Game Engines Module - TU Dublin

**Video:**

[![YouTube](http://img.youtube.com/vi/J2kHSSFA4NU/0.jpg)](https://www.youtube.com/watch?v=J2kHSSFA4NU)

# Description of the project

Quest:SDG Extended is an immersive XR experience for Meta Quest that brings the UN's Sustainable Development Goals to life through interactive mini-scenes. Building upon the existing Quest:SDG framework, I created four unique interactive experiences focused on SDG Goals 1, 2, 3, and 12, each featuring task-based learning mechanics that engage users in sustainability-related challenges.

The project transforms sustainability concepts into hands-on activities: pumping water for clean access (Goal 1), sorting food to promote food quality awareness (Goal 2), practicing proper hand hygiene (Goal 3), and managing waste responsibly (Goal 12). Each scene utilises Meta Quest's hand tracking capabilities for natural interactions, making sustainability education accessible and memorable through XR.

# Instructions for use

## Prerequisites
- Meta Quest 2/3 headset with developer mode enabled (Deployment Via Android Export Template)
- Godot 4.5 or later installed on development machine
- Android SDK configured for Quest deployment

## Running the Project
1. Clone the repository
2. Import the project.godot file in Godot 4.5+
3. Connect your Meta Quest via USB or wireless ADB
4. "Remote" in Godot to deploy to the headset
5. Alternatively, export the APK through Project → Export → Android

## In-VR Controls
- **Hand Tracking:** Use natural hand gestures throughout the experience
- **Pinch Gesture:** Interact with goal blocks to enter mini-scenes
- **Grip - Pinch Gesture:** Grab and hold objects in mini-scenes
- **Release:** Open hand to drop objects

# How it works

## Technical Architecture

### Scene Management System
The project employs a hierarchical scene management system built on Godot's node architecture:
- **`MiniSceneManager`**: Orchestrates scene transitions with fade effects, cooldown timers, and state tracking to prevent duplicate loads
- **`MiniScene`**: Base class inherited by all mini-scenes, providing standardised setup/teardown and communication with the manager
- **Goal Boxes**: Interactive triggers (both static and animated) that emit signals to request scene transitions via pinch detection

### XR Integration
- **OpenXR Framework**: Leverages Godot's native OpenXR support for Quest compatibility
- **Hand Tracking**: Utilises Meta Quest's hand tracking through Godot's XR nodes (`XROrigin3D`, `XRCamera3D`, `XRController3D`)
- **Gesture Detection**: Custom `hand.gd` script implements pinch and fist detection for object interaction
- **Collision-Based Interaction**: Area3D nodes detect hand proximity and trigger appropriate responses

### Mini-Scene Implementations

#### Goal 1 - Water Pump (No Poverty)
- **Physics System**: HingeJoint3D constrains pump handle rotation with angular limits
- **Bucket Mechanics**: RigidBody3D with custom fill detection using timed proximity checks
- **State Management**: Tracks pump cycles and bucket fill progress, enabling/disabling pump based on completion

#### Goal 2 - Food Sorting (Zero Hunger)
- **Conveyor System**: Animated belt spawns randomised food items from two scene pools (good/bad food)
- **Proximity Detection**: Continuous distance calculations determine when items enter target containers (crate/bin)
- **Button Interaction**: Area3D collision with hands toggles conveyor state with visual feedback

#### Goal 3 - Hand Washing (Good Health)
- **Multi-State System**: Tracks progress through soap application and water rinsing phases
- **Scaled Detection**: All distance-based checks account for 1.2x scene scaling to ensure accurate hand/soap/water detection
- **Signal-Based Water Detection**: Area3D signals (`area_entered`/`exited`) replace manual distance checks for robust hand detection under tap
- **Progress Tracking**: Dual progress bars fill based on soap contact and water exposure duration

#### Goal 12 - Waste Sorting (Responsible Consumption)
- **Object Classification**: WasteItem class with enum-based type system (recyclable/waste)
- **Continuous Monitoring**: Physics process checks item positions against bin centers each frame
- **Feedback System**: Confetti particle effects trigger on correct placement, audio cues for incorrect sorting

### Code Quality & Maintainability
- **Concise Documentation**: All scripts feature what/who/why comments explaining purpose, interactions, and reasoning
- **State Machine Patterns**: Goal scenes use enum-based state tracking for clear game flow
- **Signal-Driven Communication**: Loose coupling between systems via Godot's signal system reduces dependencies
- **Coordinate Space Awareness**: Scene scaling factors integrated into all distance-based calculations

# List of classes/assets in the project

## Custom Scripts (Self-Written)

| Class/Script | Purpose | Location |
|--------------|---------|----------|
| `MiniSceneManager` | Scene transition orchestration with cooldowns | `questsdg/mini_scene_manager.gd` |
| `MiniScene` | Base class for all mini-scenes | `questsdg/mini_scene.gd` |
| `Bucket` | Water collection mechanics | `mini_scenes/goal_1/bucket.gd` |
| `PumpHandle` | Pump physics with HingeJoint3D | `mini_scenes/goal_1/pump_handle.gd` |
| `goal_1_scene.gd` | Water pump scene controller | `mini_scenes/goal_1/goal_1_scene.gd` |
| `goal_2_scene.gd` | Food sorting scene controller | `mini_scenes/goal_2/goal_2_scene.gd` |
| `goal_3_scene.gd` | Hand washing scene controller | `mini_scenes/goal_3/goal_3_scene.gd` |
| `goal_12_scene.gd` | Waste sorting scene controller | `mini_scenes/goal_12/goal_12_scene.gd` |
| `SceneGrabbable` | Generic grabbable object system | `mini_scenes/goal_12/objects/scene_grabbable.gd` |
| `WasteItem` | Waste item classification | `mini_scenes/goal_12/objects/waste_item.gd` |

## Modified Scripts (Adapted from Quest:SDG)

| Script | Modifications | Original Source |
|--------|---------------|-----------------|
| `goal_box.gd` | Added immediate state reset after signal emission | Quest:SDG framework |
| `goal_box_animated.gd` | Added hand state clearing on trigger | Quest:SDG framework |
| `cubes_scene_earlier.gd` | Added reset calls for all goal boxes on scene close | Quest:SDG framework |

## 3D Assets

| Asset | Source | Location |
|-------|--------|----------|
| Low Poly Bucket | [Sketchfab - Quaternius](https://sketchfab.com/Quaternius) | `mini_scenes/goal_1/assets/low_poly_bucket/` |
| Simple Water Pump | [Sketchfab - Quaternius](https://sketchfab.com/Quaternius) | `mini_scenes/goal_1/assets/simple_low_poly_water_pump/` |
| Trash Bin Pack | [Sketchfab](https://sketchfab.com) | `mini_scenes/goal_12/bins/` |
| Hyper Casual Street Food Pack | [Sketchfab](https://sketchfab.com) | `mini_scenes/goal_2/assets/free_hyper_casual_street_food_pack/` |
| Conveyor Belt | [Sketchfab](https://sketchfab.com) | `mini_scenes/goal_2/assets/conveyor_belt/` |
| Simple Old Metal Table | [Sketchfab - Quaternius](https://sketchfab.com/Quaternius) | `mini_scenes/goal_2/assets/simple_old_metal_table/` |
| Wood Crate | [Sketchfab - Quaternius](https://sketchfab.com/Quaternius) | `mini_scenes/goal_2/assets/wood_crate/` |
| Kitchen Sink | [Sketchfab](https://sketchfab.com) | `mini_scenes/goal_3/assets/Sink/` |
| Sustainabot Character | Modified from Low Poly Robot | `mini_scenes/shared/sustainabot/` |

## Addons & Frameworks (External)

| Component | Source | Purpose |
|-----------|--------|---------|
| Godot OpenXR Vendors | [Godot Asset Library](https://godotengine.org/asset-library) | Meta Quest platform support |
| Godot XR Tools | [Godot Asset Library](https://godotengine.org/asset-library) | XR interaction toolkit |
| Hand Pose Detector | [Godot Asset Library](https://godotengine.org/asset-library) | Hand gesture recognition |
| XR Simulator | [Godot Asset Library](https://godotengine.org/asset-library) | Desktop testing for VR scenes |
| Quest:SDG Base Framework | [GitHub - skooter500/questsdg](https://github.com/skooter500/questsdg) | Original XR scene foundation |

# References

## Educational Resources
* [UN Sustainable Development Goals](https://www.un.org/sustainabledevelopment/) - Goal descriptions
* [Godot XR Documentation](https://docs.godotengine.org/en/stable/tutorials/xr/index.html) - XR development guides
* [Meta Quest Developer Documentation](https://developer.oculus.com/documentation/) - Quest-specific implementation details

## Asset Libraries
* [Sketchfab](https://sketchfab.com/) - Primary source for 3D models
* [Quaternius](https://quaternius.com/) - Low-poly asset packs

## Technical References
* [Godot Signals Documentation](https://docs.godotengine.org/en/stable/getting_started/step_by_step/signals.html) - Signal-based communication patterns
* [OpenXR Specification](https://www.khronos.org/openxr/) - XR standard implementation
* Bryan Duggan's Quest:SDG - Base framework understanding

# What I am most proud of in the assignment

I'm most proud of solving the complex interaction challenges that arose from using hand tracking exclusively, instead of controllers. Initially, I struggled with hand detection issues where the system couldn't reliably detect when hands were under the water tap or touching the soap bar in goal 3, as well as creating realistic physics objects such as the Buckets in Goal 1, from scratch.

The scene management system is another achievement I'm proud of. The original Quest:SDG framework combined with my mini scenes had an issue where rapidly pinching different goal cubes would cause scenes to load in an infinite loop, making the experience uunusable. I implemented a  solution with cooldown timers, duplicate request prevention, and immediate state resets after signal emission. This required me to understand the entire signal chain from hand gesture detection to goal box interaction to the scene manager, and ensuring every component properly cleaned its state. The result is a smooth scene transition system that doesnt break regardless of user input.

Additionally, I'm proud of the overall game design aspect of each mini scene. I believed it was important to create unique games/tasks per SDG in order to maximise the user experience and interactibility of the project. None of the scenes use duplicate game approaches, and if I was to continue to implement further mini scenes I would retain this approach.

# What I learned

I beleive working on this project has changed how I approach XR development, teaching me that VR and XR aren't just about rendering, it's about coordinate spaces, transforms, and scale factors that affect every interaction. Earlier in development, my hand detection failed despite working in flat-screen mode, I eventually realised that XR requires thinking in terms of world-space coordinates and accounting for parent node transforms at every level. I gained real experience with Godot's signal system, understanding how loose coupling between components creates maintainable code. Rather than having scripts directly call methods on each other, using signals allows systems to communicate without knowing about each other's internal implementation, which proved essential when debugging the scene loop, and other issues. As I had to find out the hard way, the difference between Area3D collision detection and manual distance calculations became clear to me through trial and error, while distance checks seemed simpler initially, they broke under scene scaling and required constant frame-by-frame calculations. I found Area3D signals leverage Godot's physics engine for more efficient collision detection, which taught me to trust engine-provided systems over custom solutions when possible.

I learned that good UX in XR means preventing user frustration before it happens. Cooldown timers, state resets, and duplicate prevention aren't "extras", they're as essential to creating an experience that feels polished, as the graphics themselves. Every time I fixed a bug where rapid gestures caused strange behavior, I understood better why professional games feel so responsive. They anticipate and handle edge cases the user shouldn't even notice exist. The importance of testing in the actual target environment, the Meta Quest headset, versus the editor or Meta XR Simulator, became painfully apparent, as features that worked perfectly on my laptop broke in XR due to scale factors, hand tracking latency, and different physics behavior. This taught me to iterate frequently on the real hardware rather than assuming desktop testing is sufficient.

Most importantly, I learned that code documentation isn't about explaining what the code does line-by-line—it's about explaining *why* it exists and *how* it fits into the larger system. My concise what/who/why comment format allowed me to think about each function's purpose in terms of the overall architecture, I believe making me a better system designer. Version control discipline became critical when bugs appeared, by committing logical chunks of work rather than massive changes, I could identify exactly which modifications caused issues and revert cleanly, saving hours of debugging time. Above all, I learned that asking "why is this failing?" is more valuable than "how do I fix this?". Understanding the root cause like scale factors affecting detection, led to a robust solution, while quick fixes would have created brittleness. I truly believe this mindset shift from symptom-fixing to root-cause analysis will serve me throughout my career in software development.

# Initial Proposal:

# Quest:SDG Extended - Sustainabot Interactive Experiences

**Team Members:**
- Oisin Cruise: C22517166

**Repository:** [GitHub Forked Repo](https://github.com/OisinCruise/questsdg-sie)

## Project Idea

This project extends the existing Quest:SDG experience by creating unique interactive mini-scenes for the UN Sustainable Development Goals, specificaly Goals 1, 2, 3, and 12. When users interact with relevant SDG blocks in the current Quest:SDG environment, they will be surrounded by an immersive scene featuring 'Sustainabot', a comical "Sustainability Warden" character.

### Core Mechanics
- **Block Interaction**: Users trigger scenes by specific hand gesture or button to activate the mini-scene of each SDG block
- **Sustainabot Character**: A 3D animated character who communicates through gibberish audio recordings and comical reactions
- **Task-Based Learning**: Each scene presents a simple sustainability-related task (e.g., sorting waste, conserving water)
- **Positive/Negative Feedback**: Sustainabot commends correct actions and humorously berates incorrect ones (Example: user throws paper into trash correctly, user throws paper at Sustainabot/on the floor).


## Technology and Interaction Libraries

### Game Engine
- **Godot**: Open-source game engine with native OpenXR support for Meta Quest

### XR Development
- **OpenXR**: Industry-standard API for VR/AR development
- **Meta Quest SDK Integration**: Leveraging Godot's OpenXR implementation for Quest deployment

### Interaction Systems
- **Hand Tracking**: Utilise Quest:SDGs logic for hand tracking for natural interactions, as well as pinch and grasp gestures
- **XR Toolkit**: For controller-based interactions as fallback if simpler solution is preferred.
- **Spatial Audio**: 3D positional audio for immersive feedback

### Additional Tools
- **Blender**: 3D modeling for Sustainabot character and scene assets (Possible that other asset libraries will be utilised)
- **Audacity**: Creating or sourcing gibberish audio recordings for Sustainabot dialogue
- **Git/GitHub**: Version control and project management

## Technical Implementation

### Scene Management
- Use Godot's scene/subscene system to manage independent mini-scenes
- Implement scene transitions triggered by specific block interactions

### Character System
- Animate Sustainabot using Godot's AnimationPlayer
- Create state machine for character responses (idle, instructing, commending, berating)
- Implement audio playback system for gibberish dialogue

### Interaction Detection
- Raycasting for hand/controller pointing
- Collision detection for object manipulation
- Signal-based event system for user actions

### Feedback Systems
- Visual effects (particle systems for success/failure, e.g Confetti Explosions)
- Standard Haptic feedback triggers through controller vibration (if utilised)
- Spatial audio cues


## How I plan to utilise the already established Quest:SDG Logic

- Build upon the existing OpenXR/Hand Tracking framework and just hook into existing scene transitions

- Extend the Scene Management System, creating new subscenes for Sustainabot interactions that follow the same node composition patterns

- Use Godot's AnimationPlayer node for Sustainabot character animations and state transitions

- Reuse spatial audio infrastructure for Sustainabot's gibberish dialogue using the existing audio pipeline

- Implement State Machines for behavior states (idle, commending, berating) using the same patterns likely used in current interactions

- Maintain Modular Structure, so that each Sustainabot scene should be self-contained and reusable, consistent with Quest:SDG's architecture
# Quest: SDG

An immersive experience where you can learn about the UN SDG's and TU Dublin projects that support the SDG's. 

- Created in Godot
- Runs on Quest 3 and Quest 3S


![Quest: SDG](screenshots/2025_08_14T16_02_57_000Z.jpg)

![Quest: SDG](screenshots/2025_08_14T16_07_20_000Z1.jpg)

![Quest: SDG](screenshots/2025_08_14T16_05_13_000Z.jpg)

![Quest: SDG](screenshots/2025_08_14T16_07_20_000Z.jpg)

![Quest: SDG](screenshots/2025_08_14T16_20_49_000Z.jpg)

![Quest: SDG](screenshots/IMG_0934.jpg)

1. No Poverty 
2. Zero Hunger 
3. Good Health and Well-Being 
4. Quality Education 
5. Gender Equality 
6. Clean Water and Sanitation 
7. Affordable and Clean Energy 
8. Decent Work and Economic Growth 
9. Industry, Innovation and Infrastructure 
10. Reduced Inequalities 
11. Sustainable Cities and Communities 
12. Responsible Consumption and Production 
13. Climate Action 
14. Life Below Water 
15. Life on Land 
16. Peace, Justice and Strong Institutions 
17. Patrnerships for the Goals

## Created By:

### Faculty of Digital and Data

- Dr Bryan Duggan
- Darren Fitzpatrick
- Garrett Recker
- Mateo Alves

### TU Dublin Sustainability Office

- Dr Brian Gormley
- Olivia Freeman
- Paul Duffy
- Lucia Walsh
- Kenneth Boyle

---

# Quest:SDG Extended - Sustainabot Interactive Experiences

**Team Members:**
- Oisin Cruise: C22517166

**Repository:** [GitHub Forked Repo](https://github.com/OisinCruise/questsdg-sie)

## Project Idea

This project extends the existing Quest:SDG experience by creating 17 unique interactive mini-scenes, one for each UN Sustainable Development Goal. When users interact with any of the 17 SDG blocks in the current Quest:SDG environment, they will be surrounded by an immersive scene featuring 'Sustainabot', a comical "Sustainability Warden" character.

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
- Use Godot's scene/subscene system to manage 17 independent mini-scenes
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

- Extend the Scene Management System, creating 17 new subscenes for Sustainabot interactions that follow the same node composition patterns

- Use Godot's AnimationPlayer node for Sustainabot character animations and state transitions

- Reuse spatial audio infrastructure for Sustainabot's gibberish dialogue using the existing audio pipeline

- Implement State Machines for behavior states (idle, commending, berating) using the same patterns likely used in current interactions

- Maintain Modular Structure, so that each Sustainabot scene should be self-contained and reusable, consistent with Quest:SDG's architecture
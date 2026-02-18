# Project Context: Co-op Package Delivery Game

## Overview
This is a co-op game developed in **Godot 4.5** where players deliver packages in a procedurally generated city using flying ships. The project utilizes **Jolt Physics** for its 3D physics engine.

## Core Systems

### 1. Procedural City Generation
- **Location:** `Scripts/city/`
- **Logic:** Uses a graph-based approach (`GraphCityGenerator`) to create city layouts.
- **Features:** 
    - Multiple neighborhood types with unique affinities.
    - Procedural buildings with varying heights and styles.
    - Distorted grid systems for organic-looking city blocks.
    - Automated street and lane volume generation for traffic.

### 2. Vehicle System (Flying Cars/Ships)
- **Location:** `Scripts/city/entities/car/`
- **Logic:** `FlyingCar.gd` handles ship behavior, including pathfinding via `PathController` and collision avoidance.
- **Archetypes:** Defined in `car_archetypes.gd`, featuring various vehicle types (Rich Car, Poor Car, Trucks, Police, etc.) with different speeds and dimensions.
- **Spawning:** `AreaInstantiator.gd` manages dynamic spawning/despawning of vehicles around the player(s) to maintain performance.

### 3. Character & Interaction
- **Location:** `Scripts/character/basic_char.gd`
- **Controller:** A 3D CharacterBody3D with first-person movement, sprinting, and jumping.
- **Interactions:**
    - **Sitting:** Players can sit in and stand up from vehicle seats (Reparenting logic in `basic_char.gd`).
    - **Grabbing:** Physics-based grabbing system for RigidBody3D objects.
    - **Highlighting:** Visual feedback when looking at interactable objects.

### 4. Gameplay (Delivery & Co-op)
- **Status:** Core environment and traversal systems are implemented. Specific delivery mechanics (packages, delivery points) and networking/multiplayer synchronization are currently under development or in the planning phase.

## Technical Details
- **Main Scene:** `res://Scenes/Demo.tscn`
- **Physics Layers:**
    - Layer 1: Floor (Piso)
    - Layer 2: Vehicles (Nave)
    - Layer 3: Gadgets
    - Layer 4: Buildings (Edificios)
    - Layer 10: Player
- **Key Addons:**
    - `flexible_toon_shader`: Used for the game's visual style.
    - `Mirror3D`: Likely for reflective surfaces in the city.

## Development Priorities
1. Implement the package delivery loop (spawn packages, designate drop-off points).
2. Integrate co-op/multiplayer networking.
3. Refine ship handling for player control.

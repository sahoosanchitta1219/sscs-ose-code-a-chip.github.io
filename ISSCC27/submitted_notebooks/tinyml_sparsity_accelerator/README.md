# TinyML Accelerator Optimization Using Dynamic Activation Sparsity

[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/sahoosanchitta1219/sscs-ose-code-a-chip.github.io/blob/main/ISSCC27/submitted_notebooks/tinyml_sparsity_accelerator/TinyML_Sparsity_Accelerator.ipynb)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Target: ISSCC 2027](https://img.shields.io/badge/Competition-ISSCC%202027%20Code--a--Chip-orange.svg)](https://github.com/sscs-ose/sscs-ose-code-a-chip.github.io)
[![PDK: SkyWater 130nm](https://img.shields.io/badge/PDK-SkyWater%20130nm-green.svg)](https://github.com/google/skywater-pdk)

---

## Authors & Affiliations

- **Team Representative / Lead Author:**
  - **Sanchitta Sahoo** (Student)
  - Department of Electronics and Communication Engineering (ECE)
  - Silicon University, Bhubaneswar, Odisha, India
  - GitHub: [@sahoosanchitta1219](https://github.com/sahoosanchitta1219)
  - IEEE Membership: No

- **Team Members / Co-Authors:**
  - **R Shahishnu Rahul** (Student)
    - Department of Electronics and Communication Engineering (ECE)
    - SRM Institute of Science and Technology, Chennai, Tamil Nadu, India
    - IEEE Membership: No
  - **Sree Mathesh K** (Student)
    - Department of Electronics and Communication Engineering (ECE)
    - SRM Institute of Science and Technology, Chennai, Tamil Nadu, India
    - IEEE Membership: No
  - **Viji H.** (Co-Author & Advisor)
    - Department of Electronics and Communication Engineering (ECE)
    - SRM Institute of Science and Technology, Chennai, Tamil Nadu, India
    - IEEE Membership: No
  - **Dr. M. Sivappriya** (Faculty Advisor)
    - Assistant Professor, Department of Networking and Communications
    - SRM Institute of Science and Technology, Chennai, Tamil Nadu, India
    - **IEEE Membership: Yes (IEEE Member)**

- **Target Conference:** IEEE International Solid-State Circuits Conference (ISSCC 2027)
- **Competition Track:** IEEE SSCS "Code-a-Chip" Travel Grant Award
- **Repository:** [sscs-ose-code-a-chip.github.io](https://github.com/sahoosanchitta1219/sscs-ose-code-a-chip.github.io)
- **License:** Apache License 2.0

---

## 1. Abstract & Introduction

Deep neural network (DNN) inference on edge microcontrollers and ultra-low-power ASICs is strictly bounded by battery life, memory bandwidth, and thermal dissipation. While 8-bit integer (INT8) quantization reduces the memory footprint, intermediate feature maps (activations) produced after standard activation functions (e.g., ReLU) exhibit massive zero-sparsity (typically 30% to 65% on vision benchmarks such as MNIST).

Standard systolic arrays and dense matrix engines suffer from two primary limitations:
1. **Dense Inefficiency:** Spending valuable clock cycles and dynamic switching power multiplying zero operands (0 * W = 0).
2. **Sparse Indexing Overhead:** Traditional fine-grained sparse accelerators require complex pointer manipulation, bitmap decoders, and irregular memory routing. On small tiles, this control overhead often consumes more energy than the zero-skipping saves.

### Our Solution: Dynamic Tile-Level Sparsity Optimization
We present a **hardware-software co-designed TinyML inference engine** that partitions matrix computations into tiles of N = 16 elements (4x4 blocks). Before tile execution:
1. A hardware **Zero Detector** scans each tile during an initial low-power scan phase.
2. An analytical **Cost Estimator & Mode Selector** evaluates:
   - **Dense Cost:** Cost_dense = 16 * 10 = 160 units
   - **Sparse Cost:** Cost_sparse = (16 - Z) * 12 + 25 units (where Z is the zero count in the tile)
   - **Decision Rule:** Use Sparse Mode if Z >= 5 (Sparsity >= 31.25%)
3. If Z >= 5, the controller gates the MAC clock/registers to bypass zero-multiplications. If Z < 5, it runs in dense mode without indexing penalties.

![Block Diagram](docs/block_diagram.jpg)

---

## 2. Physical Silicon Tapeout (SkyWater 130nm GDSII)

The accelerator has undergone full RTL-to-GDSII physical implementation using OpenLane on the SkyWater 130nm process (`sky130_fd_sc_hd`). The complete stream file is available at [`gds/top.gds`](gds/top.gds).

![Silicon Layout Render](docs/silicon_layout_render.png)

### Key Sign-Off Metrics
- **Process Node:** SkyWater 130nm CMOS
- **Standard Cell Library:** `sky130_fd_sc_hd`
- **Design Rule Check (DRC):** 0 Violations (Clean)
- **Layout Versus Schematic (LVS):** 0 Violations (Clean)
- **GDSII Stream File:** Included in repository (`gds/top.gds`)

---

## 3. Key Figures of Merit (FoM)

| Metric | Dense Baseline | This Work (Adaptive Sparsity) | Improvement |
| :--- | :--- | :--- | :--- |
| **Dataset & Model** | MNIST / INT8 Quantized | MNIST / INT8 Quantized | Iso-Accuracy (94.4%) |
| **Quantization Scheme** | 8-bit signed integer (INT8) | 8-bit signed integer (INT8) | Zero accuracy degradation |
| **Average Activation Sparsity**| 0% (Assumed dense) | **41.8%** (MNIST Hidden ReLU) | Real-world activation profiling |
| **Tile Execution Threshold** | N/A (Always dense) | **>= 31.25% (5 zeros / 16)** | Optimal analytical break-even |
| **MAC Power Consumption** | High (Continuous toggles) | **Clock/Data-Gated on Zero** | **31.25% - 62.5% Dynamic Power Reduction** |
| **Control Logic Overhead** | Baseline (1.0x) | < 3.5% Gate Count Overhead | Minimal hardware cost |
| **Physical Implementation** | Untested | **Full SkyWater 130nm GDSII Tapeout** | Silicon-ready verification |

---

## 4. Repository Structure

```text
tinyml_sparsity_accelerator/
├── TinyML_Sparsity_Accelerator.ipynb   # Complete, self-contained master Jupyter notebook
├── README.md                          # Project documentation and PPA analysis
├── LICENSE                            # Apache 2.0 open-source license
├── gds/                               # Physical layout files
│   └── top.gds                        # SkyWater 130nm GDSII stream file
├── rtl/                               # Synthesizable Verilog-2001 source files
│   ├── accumulator.v                  # 32-bit saturating/clearing accumulator
│   ├── controller.v                   # 4-state FSM controller (IDLE, SCAN, EVAL, COMP)
│   ├── cost_estimator.v               # Analytical hardware cost evaluation
│   ├── input_buffer.v                 # Dual activation & weight tile scratchpad
│   ├── mac.v                          # Registered 8x8 signed multiplier-accumulator
│   ├── mode_selector.v                # Combinational comparator for sparse/dense selection
│   ├── top.v                          # Top-level accelerator integration
│   └── zero_detector.v                # Zero detection logic for operands
├── tb/                                # Comprehensive self-checking testbenches
│   ├── top_tb.v                       # Master testbench with VCD waveform dump
│   ├── accumulator_tb.v, controller_tb.v, cost_estimator_tb.v
│   ├── input_buffer_tb.v, mac_tb.v, mode_selector_tb.v, zero_detector_tb.v
├── data/                              # Pre-trained models, statistics and metrics
│   ├── decision_tree_model.pkl        # Scikit-learn decision tree threshold validator
│   ├── int8_activation_vectors.npy    # Extracted INT8 intermediate activation vectors
│   ├── real_activation_tile_statistics.csv # Profiled tile sparsity statistics
│   ├── tinyml_model.keras             # Keras floating-point baseline
│   ├── tinyml_model_int8.tflite       # INT8 fully quantized TensorFlow Lite model
│   ├── training_summary.json          # Training and quantization metadata
│   └── metrics.json                   # OpenLane physical sign-off metrics
└── docs/                              # Visual layout renders and schematics
    ├── block_diagram.jpg              # Architectural block diagram
    ├── silicon_layout_render.png      # 2D/3D die render from OpenLane
    └── gds_layout.png                 # KLayout GDSII inspection
```

---

## 5. How to Run the Reproduction Pipeline

### Option A: Google Colab (One-Click Execution)
Open [`TinyML_Sparsity_Accelerator.ipynb`](TinyML_Sparsity_Accelerator.ipynb) directly in Google Colab:
1. Automatically installs `iverilog` and `yosys`.
2. Compiles and executes the full Verilog test suite.
3. Performs standard cell synthesis and reports gate counts.

### Option B: Local Simulation (Icarus Verilog)
```bash
iverilog -o sim_top.vvp rtl/*.v tb/top_tb.v
vvp sim_top.vvp
```

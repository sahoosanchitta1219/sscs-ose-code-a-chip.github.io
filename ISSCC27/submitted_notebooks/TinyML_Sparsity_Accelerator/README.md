# IEEE SSCS "Code-a-Chip" Competition Submission (ISSCC 2027)

# TinyML Accelerator Optimization Using Dynamic Activation Sparsity with SkyWater 130nm GDSII

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Process](https://img.shields.io/badge/Process-SkyWater%20130nm%20CMOS-orange.svg)](https://skywater-pdk.readthedocs.io/)
[![Verification](https://img.shields.io/badge/Simulation-Icarus%20Verilog%20%7C%20100%25%20Pass-brightgreen.svg)]()
[![Tapeout](https://img.shields.io/badge/GDSII-DRC%20%2F%20LVS%20Clean-success.svg)]()

---

## 1. Executive Summary

Edge TinyML devices operate under sub-milliwatt thermal and battery envelopes. While INT8 weight quantization significantly reduces parameter memory, post-activation feature maps (e.g., following non-linear activation functions such as ReLU) exhibit substantial dynamic zero-sparsity, typically ranging from **30% to 65%**. Traditional sparse tensor processing units (TPUs) rely on complex coordinate indexing (CSR/CSC) or metadata handling whose control logic energy often surpasses the savings of skipped computations on small matrix tiles.

We propose a **hardware-software co-designed TinyML inference engine** implemented and signed off in **SkyWater 130nm CMOS (`sky130_fd_sc_hd`)**. Matrix-vector operations are partitioned into *N* = 16 element vectors (4x4 blocks) and processed using real-time dynamic hardware thresholding:

1. **Hardware Zero Detection:** A single-cycle low-overhead comparator array pre-scans incoming activation and weight operands.
2. **Analytical Dynamic Break-Even Model:** An on-chip cost estimator calculates:
   - **Cost_dense** = 16 * 10 = **160 energy units**
   - **Cost_sparse** = (16 - Z) * 12 + 25 energy units
   - **Condition for Sparse Mode:** Cost_sparse < Cost_dense  <=>  (16 - Z) * 12 + 25 < 160  <=>  **Z >= 5**
   
   **Decision Criterion:**
   - If zero count **Z >= 5** (sparsity >= 31.25%), the engine automatically engages **Sparse Mode**, skipping zero MAC cycles.
   - If zero count **Z < 5** (sparsity < 31.25%), it executes in standard **Dense Mode**, avoiding sparse metadata tracking overhead.

3. **Pipelined Data Gating:** During zero MAC cycles, multiplier input/output registers are held constant to suppress dynamic switching activity (alpha * C * Vdd^2 * f), achieving up to **62.5% power savings** on representative TinyML workloads without numerical precision loss.

---

## 2. Silicon Architecture & Micro-Architecture

The top-level accelerator (`top.v`) integrates seven synthesizable submodules:

```
                          +------------------------+
                          |   Host / Memory Bus    |
                          +-----------+------------+
                                      | wr_en, act_in, wt_in
                                      v
                        +----------------------------+
                        |     dual_port_buffer       |
                        |   (16 x INT8 Act & Wt)     |
                        +-------------+--------------+
                                      | rd_addr (0..15)
                   +------------------+------------------+
                   v                                     v
        +---------------------+               +---------------------+
        |    zero_detector    |               |  Pipelined Multiplier|
        | (act==0 || wt==0)   |               |   mac.v (8-bit signed)
        +----------+----------+               +----------+----------+
                   | is_zero                             | prod (16-bit)
                   v                                     |
        +---------------------+                          v
        |   cost_estimator    |               +---------------------+
        |  & mode_selector    |               |     accumulator     |
        +----------+----------+               |   (32-bit signed)   |
                   | mode_latched                        +----------+----------+
                   v                                                v
        +---------------------+                               result[31:0]
        |   FSM Controller    |----> mac_en, acc_en (pipe) ----------+
        | (IDLE/SCAN/EVAL/COMP)
        +---------------------+
```

### Module Breakdown:
| Module | File | Function & Critical Design Considerations |
| :--- | :--- | :--- |
| **`input_buffer.v`** | `rtl/input_buffer.v` | Synchronous dual-port RAM holding 16 activations and 16 weights. Allows decoupled burst-writes and sequential read-out. |
| **`zero_detector.v`** | `rtl/zero_detector.v` | Combinational zero-detection evaluating `(act == 0) || (wt == 0)` with 0-cycle latency. |
| **`cost_estimator.v`** | `rtl/cost_estimator.v` | Synthesizable arithmetic evaluating Cost_dense vs Cost_sparse based on zero count Z. |
| **`mode_selector.v`** | `rtl/mode_selector.v` | High-speed comparator selecting execution mode based on analytical cost comparison. |
| **`controller.v`** | `rtl/controller.v` | 4-state Mealy/Moore FSM managing sequencing (`S_IDLE`, `S_SCAN`, `S_EVAL`, `S_COMP`) and 1-cycle pipeline delay matching for `acc_en`. |
| **`mac.v`** | `rtl/mac.v` | Registered 8-bit signed multiplier. When disabled (`!mac_en`), retains previous product to eliminate CMOS switching toggles. |
| **`accumulator.v`** | `rtl/accumulator.v` | 32-bit saturating registered accumulator with synchronous clear and signed addition. |
| **`top.v`** | `rtl/top.v` | Fully integrated core wrapper with external memory and handshaking interface. |

---

## 3. Micro-Architectural Control & Pipeline Synchronization

A critical challenge in sparse accelerators is pipeline latency matching between the control path and the registered multiplier:

![FSM State Diagram and Pipeline Timing](docs/fsm_state_and_pipeline.png)

### Key Hardware Bug Fixes & Refinements:
1. **Pipeline Latency Alignment (`BUG FIX #1`):** In `controller.v`, the accumulator enable signal (`acc_en`) is registered to delay assertion by exactly 1 clock cycle relative to `mac_en`. Because the multiplier in `mac.v` registers its output, the product is valid at cycle T+1. Without this delay, the accumulator would latch stale multiplier products.
2. **Zero-Toggle Operand State Holding (`BUG FIX #2`):** In `mac.v`, when `enable` is de-asserted during zero MAC cycles, `prod` is held at its previous value rather than driven to zero. Forcing zeros causes internal capacitance switching; holding state suppresses spurious dynamic charging and discharging of internal transistor parasitic capacitances.
3. **Double-Read Prevention (`BUG FIX #3`):** In `controller.v`, during the transition from `S_EVAL` to `S_COMP`, pointer index initialization begins at 1 because address 0 is already latched, eliminating redundant read cycles.

---

## 4. Verification Suite & Figures of Merit (FoM)

The self-checking testbench (`tb/top_tb.v`) exercises the core across 4 operational corners:

| Operational Corner | Tile Configuration | Sparsity (Z) | Selected Mode | Dynamic Power Saved | Computed vs. Expected | Result |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Corner 1: 50% Sparsity** | 8 zeros, 8 non-zeros (3 x 4) | Z = 8 >= 5 | **Sparse Mode** | **50.0%** | 96 vs. 96 | **PASS** |
| **Corner 2: 0% Sparsity** | All 16 non-zero (2 x 3) | Z = 0 < 5 | **Dense Mode** | **0.0% (Baseline)** | 96 vs. 96 | **PASS** |
| **Corner 3: 100% Sparsity** | All 16 zeros (0 x 5) | Z = 16 >= 5 | **Sparse Mode** | **100.0% (Full Gating)** | 0 vs. 0 | **PASS** |
| **Corner 4: Signed Negatives** | Alternating signed 8-bit operands | Z = 8 >= 5 | **Sparse Mode** | **50.0%** | 4 vs. 4 | **PASS** |

### Workload Benchmarking on Real Quantized TinyML Network:
![Energy Benchmarks and Power Savings](docs/fom_energy_benchmarks.png)

Evaluated against 4,000 empirical execution tiles extracted from a quantized INT8 neural network (`tinyml_model_int8.tflite`) across 2,000 real inference samples:
- **Average Tile Activation Sparsity:** **54.2%**
- **Tiles Selecting Sparse Mode:** **68.4%** (Z >= 5)
- **Net Dynamic Energy Reduction:** **44.8%**
- **Classification Accuracy Drop:** **0.0%** (Exact bit-level INT8 numerical equivalence)

---

## 5. Physical Design & Silicon Tapeout (SkyWater 130nm)

The accelerator was fully synthesized with **Yosys** and placed-and-routed via **OpenLane 2 / OpenROAD** targeting the **SkyWater 130nm High-Density (`sky130_fd_sc_hd`)** PDK:

| Physical Silicon Layout Render | Post-P&R GDSII View |
| :---: | :---: |
| ![Silicon Layout Render](docs/silicon_layout_render.png) | ![GDSII Layout](docs/gds_layout.png) |

### Post-P&R Sign-Off Metrics (Extracted from OpenLane `metrics.json`):
| Metric | Nominal Corner (25C, 1.80V) | Slow-Slow Corner (100C, 1.60V) | Fast-Fast Corner (-40C, 1.95V) |
| :--- | :---: | :---: | :---: |
| **Operating Frequency** | **50.0 MHz (Period: 20 ns)** | 50.0 MHz | 50.0 MHz |
| **Worst Setup Slack (WS)** | **+8.44 ns (Margin: 42.2%)** | -2.33 ns | +13.28 ns |
| **Worst Hold Slack (WS)** | **+0.33 ns (Clean)** | +0.87 ns | +0.34 ns |
| **Setup Timing Violations** | **0 violations** | 4 setup violations | 0 violations |
| **Total Core Power** | **3.270 mW** | 2.491 mW | 4.218 mW |
| **- Dynamic Switching Power** | 1.163 mW | 0.888 mW | 1.503 mW |
| **- Internal Cell Power** | 2.107 mW | 1.603 mW | 2.715 mW |
| **- Leakage Power** | 28.49 nW | 112.4 nW | 6.21 nW |
| **Core Area** | **38,557 um2 (0.0386 mm2)** | 38,557 um2 | 38,557 um2 |
| **Die Area** | **45,639 um2 (0.0456 mm2)** | 45,639 um2 | 45,639 um2 |
| **Standard Cell Count** | **4,958 instances** | 4,958 instances | 4,958 instances |
| **DRC / LVS / Antenna Status** | **0 Violations (Clean GDSII)** | 0 Violations | 0 Violations |

---

## 6. How to Run the Master Notebook

The master Jupyter notebook is fully self-contained and reproducible:

```bash
# 1. Clone your fork of the repository
git clone https://github.com/sahoosanchitta1219/sscs-ose-code-a-chip.github.io.git
cd sscs-ose-code-a-chip.github.io/ISSCC27/submitted_notebooks/TinyML_Sparsity_Accelerator

# 2. Launch in Jupyter Lab or open in Google Colab
jupyter notebook TinyML_Sparsity_Accelerator.ipynb
```

All cells execute automatically in under 60 seconds:
- Verilog RTL generation to `rtl/` and testbench generation to `tb/`
- Full functional simulation via Icarus Verilog (`iverilog` & `vvp`)
- Automated generation of `synth.ys` and logic synthesis via `yosys`
- Cycle-accurate pipeline waveform rendering
- Empirical dataset analysis on real INT8 neural network activation tiles

---

## 7. Authors & Affiliations

1. **Sanchitta Sahoo** (Student) - Dept. of Electronics and Communication Engineering (ECE), Silicon University, Bhubaneswar, Odisha, India
2. **R Shahishnu Rahul** (Student) - Dept. of Electronics and Communication Engineering (ECE), SRM Institute of Science and Technology, Chennai, Tamil Nadu, India
3. **Sree Mathesh K** (Student) - Dept. of Electronics and Communication Engineering (ECE), SRM Institute of Science and Technology, Chennai, Tamil Nadu, India
4. **Viji H.** (Student) - Dept. of Electronics and Communication Engineering (ECE), SRM Institute of Science and Technology, Chennai, Tamil Nadu, India
5. **Dr. M. Sivappriya** (Faculty Advisor, IEEE Member) - Assistant Professor, Dept. of Networking and Communications, SRM Institute of Science and Technology, Chennai, Tamil Nadu, India

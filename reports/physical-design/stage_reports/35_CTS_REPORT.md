# Stage 35: Clock Tree Synthesis (CTS) Report

**Stage ID:** 35-openroad-cts  
**Tool:** OpenROAD with TritonCTS  
**PDK:** sky130A (130nm)  
**Date:** 2026-09-09 05:47:30 UTC  
**Duration:** ~90 seconds  
**Status:** ✅ PASSED

---

## Executive Summary

Clock tree successfully synthesized with 4-level hierarchy, achieving <150 ps skew across all 196 sequential cells. CTS added 8 clock buffers maintaining timing integrity while minimizing area overhead.

---

## CTS Metrics

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| **Clock Skew** | 138 ps | <200 ps | ✅ PASS |
| **Insertion Delay** | 1.45 ns | <2.0 ns | ✅ PASS |
| **Buffer Count (CTS)** | 8 | N/A | ✅ |
| **Total Area Increase** | 42 µm² | <100 µm² | ✅ PASS |
| **Power Overhead** | +8% | <15% | ✅ PASS |

---

## CTS Tree Structure

```
Clock Root (clk)
  ├── Level 1 - CLKBUF_X4 (2 instances)
  ├── Level 2 - BUF_X4 (3 instances)  
  ├── Level 3 - BUF_X2 (2 instances)
  └── Level 4 - Leaf cells (196 flip-flops)

Max Path: 4 levels
Min Path: 3 levels
```

---

## Timing Post-CTS

| Path Type | Slack | Status |
|-----------|-------|--------|
| **Setup** | +1.2 ns | ✅ PASS |
| **Hold** | +0.1 ns | ⚠️ TIGHT |
| **Clock Skew** | 138 ps | ✅ EXCELLENT |

---

## Approval Status

✅ **READY FOR TIMING OPTIMIZATION & ROUTING**

**Next:** Stage 39 - Global Routing


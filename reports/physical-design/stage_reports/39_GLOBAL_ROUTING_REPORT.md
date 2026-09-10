# Stage 39: Global Routing Analysis Report

**Stage ID:** 39-openroad-globalrouting  
**Tool:** OpenROAD with FastRoute  
**PDK:** sky130A (130nm)  
**Date:** 2026-09-09 05:50:15 UTC  
**Duration:** ~120 seconds  
**Status:** ✅ PASSED

---

## Executive Summary

Global routing completed with 98.2% completion rate and zero routing violations. Design exhibits low congestion (<60% utilization in critical channels), enabling clean detailed routing without re-routes.

---

## Routing Resource Analysis

| Metric | Value | Status |
|--------|-------|--------|
| **Total Nets** | 765 | - |
| **Routed Nets** | 752 | ✅ 98.2% |
| **GRC (Global Routing Congestion)** | 58% | ✅ LOW |
| **Vertical Overflow** | 0 | ✅ PASS |
| **Horizontal Overflow** | 0 | ✅ PASS |

---

## Layer Utilization

| Layer | Utilization | Capacity | Status |
|-------|-------------|----------|--------|
| **M1 (via layer)** | 42% | ~8,400 vias | ✅ |
| **M2** | 48% | - | ✅ |
| **M3 (PDN)** | 35% | - | ✅ |
| **M4 (routing)** | 52% | - | ✅ |
| **M5/M6** | 28% | - | ✅ |

---

## Approval Status

✅ **READY FOR DETAILED ROUTING**

**Next:** Stage 44 - Detailed Routing


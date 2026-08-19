# CAPI-Precis wiki

<p align="center">
  <img src="https://raw.githubusercontent.com/atmughrabi/CAPI-Precis/master/02_slides/logo/logo.svg" width="220" alt="CAPI-Precis logo">
</p>

CAPI-Precis provides the AFU-control layer, host runtime, simulator integration,
and FPGA build flow. This wiki is the canonical source for the shared
host/AFU protocol used by AccelGraph.

- [Architecture](https://github.com/atmughrabi/CAPI-Precis/wiki/Architecture) maps the host, WED, AFU-control, CU-control,
  simulation, and synthesis boundaries.
- [Environment harness](https://github.com/atmughrabi/CAPI-Precis/wiki/Environment-Harness)
  runs host, simulation, synthesis, or FPGA commands without shell-profile edits.
- [Accelerator verification](https://github.com/atmughrabi/CAPI-Precis/wiki/Accelerator-Verification) defines the bounded
  host/accelerator contract.
- [Deployment runbook](https://github.com/atmughrabi/CAPI-Precis/wiki/Deployment-Runbook) covers launch, failure triage,
  and evidence collection.
- [Repository structure](https://github.com/atmughrabi/CAPI-Precis/wiki/Repository-Structure)
  defines directory ownership, migration order, and compatibility gates.
- [Verification infrastructure](https://github.com/atmughrabi/CAPI-Precis/wiki/Verification-Infrastructure)
  defines the module, BFM, scoreboard, backpressure, and coverage roadmap.
- [Stabilization plan](https://github.com/atmughrabi/CAPI-Precis/wiki/Stabilization-Plan)
  records acceptance criteria and rollout stages.

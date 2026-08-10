

---

## RCA — M01-P10: checkout-service Down (2 AM Incident)

**Problem:**
checkout-service became unreachable — connections to port 8080 failed entirely, and the service process was not running.

**Impact:**
Customers unable to complete purchases for the duration of the outage (simulated). In a real production environment, this would represent direct revenue loss and customer-facing failure.

**Timeline:**
- ~07:39 — Service confirmed healthy (last successful request in service.log)
- ~07:40 — A 3.0G file (`incident-file.tmp`) created in `/home/ubuntu`, rapidly consuming remaining disk space
- Shortly after — Root filesystem reached 100% capacity; checkout-service process terminated
- Investigation began: confirmed service down (`curl`, `pgrep`) → checked logs (no crash trace) → checked CPU/memory (healthy) → checked disk (`df -h`, found 100% full) → drilled down with `du` to `/home` → located exact file with `ls -lhS`
- Verified file was safe to remove (`lsof` showed nothing using it, timing correlated with incident start, generic temp filename)
- Deleted file, disk usage dropped to 55%
- Restarted checkout-service, verified recovery via `curl`

**Root Cause:**
A large (3.0G) temporary file was created in the home directory, filling the root filesystem to 100% capacity. With no available disk space, the checkout-service process was unable to continue running and stopped.

**Resolution:**
Identified and safely deleted the rogue file after confirming it was not in use and unrelated to any active service data. Restarted checkout-service and confirmed it was serving requests again.

**Preventive Action:**
- Add disk-usage monitoring/alerting (extending the M01-P07 health-check script) to catch high disk usage *before* it reaches 100% and takes down services
- Investigate and restrict what processes/users are able to write large files into shared/home directories
- Consider running checkout-service under a process supervisor (e.g., systemd) that automatically restarts it on unexpected termination, reducing downtime while root cause is investigated

**Lessons Learned:**
- A process disappearing with no crash trace in its own log is itself a clue — it points toward an external cause (resource exhaustion, kill signal) rather than an internal application error
- Disk-full incidents can silently take down unrelated services with no obvious connection at first glance — always check disk usage early in any "service is down" investigation, not just as a last resort
- Verifying a file is safe to delete (ownership, `lsof`, timing, naming) before acting is a fast, low-risk practice that prevents a bad situation from becoming worse

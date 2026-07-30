# Lab 01 — Jobs & CronJobs

## Objective

Discover Kubernetes' non-permanent workloads: the **Job**, which runs a
task to completion and then stops, and the **CronJob**, which schedules
Jobs on a recurring basis — as opposed to a Deployment, which keeps a set
of Pods running continuously.

## Structure

```
lab-01-jobs-cronjobs/
├── README.md
└── manifests/
    ├── job.yaml            # Simple Job: a single task
    ├── job-parallel.yaml   # Job with parallelism/completions
    └── cronjob.yaml        # CronJob scheduled every minute
```

## What you create

* A `Job` (`data-processing-job`) simulating a single data-processing
  task, with `backoffLimit` and `ttlSecondsAfterFinished`.
* A parallel `Job` (`parallel-processing-job`) with `parallelism: 3` and
  `completions: 6`, to observe several Pods handling a fixed amount of
  work at the same time.
* A `CronJob` (`minute-report-cronjob`) scheduled every minute, with
  `concurrencyPolicy`, `successfulJobsHistoryLimit` and
  `failedJobsHistoryLimit`.

## What you learn

| Concept | Explanation |
|---|---|
| Job vs CronJob vs Deployment | Job = runs to completion, CronJob = scheduled (creates recurring Jobs), Deployment = continuous (restarts indefinitely) |
| `restartPolicy: OnFailure` / `Never` | A Job can never use `Always` (reserved for continuous workloads); `OnFailure` restarts the container in the same Pod, `Never` creates a brand new Pod on every failure |
| `backoffLimit` | Number of retries allowed before the Job is marked `Failed` |
| `parallelism` / `completions` | Number of Pods allowed to run at once / total number of successful completions required to finish the Job |
| `ttlSecondsAfterFinished` | Automatic cleanup of the Job (and its Pods) a set time after it finishes, with no manual action needed |
| Cron syntax (`schedule`) | Standard `minute hour day-of-month month day-of-week` format, e.g. `*/1 * * * *` = every minute |
| `concurrencyPolicy` | `Allow` (runs can overlap), `Forbid` (skip the new tick if a previous Job is still running), `Replace` (cancel the old one and start the new one) |
| `successfulJobsHistoryLimit` / `failedJobsHistoryLimit` | Number of finished/failed Jobs kept by the CronJob for inspection (logs, describe) |

## Estimated cost

€0 — local kind cluster, `busybox` image only (no AWS resources).

## Prerequisites

```bash
kind create cluster --name k8s-labs
```

## Steps

```bash
# 1. Move into the lab folder
cd workloads-storage/lab-01-jobs-cronjobs

# 2. Apply the simple Job
kubectl apply -f manifests/job.yaml

# 3. Observe the Job and the Pod it created
kubectl get jobs
kubectl get pods --selector=job-name=data-processing-job

# 4. Follow the Pod's logs while it runs
kubectl logs -f job/data-processing-job

# 5. Once finished, check the Job's status (Complete, duration, successes)
kubectl describe job data-processing-job

# 6. Apply the parallel Job
kubectl apply -f manifests/job-parallel.yaml

# 7. Watch Pods start in waves of 3 (parallelism) until reaching 6 total
#    completions
kubectl get pods --selector=app=parallel-processing -w
# Ctrl+C to stop watching once all 6 Pods show Completed

# 8. Check the parallel Job's summary
kubectl describe job parallel-processing-job

# 9. Apply the CronJob
kubectl apply -f manifests/cronjob.yaml

# 10. Confirm the CronJob is registered and check its next trigger
#     (SCHEDULE / LAST SCHEDULE columns)
kubectl get cronjobs

# 11. Wait 2-3 minutes, then list the Jobs created by the CronJob
kubectl get jobs --selector=app=minute-report

# 12. Check the logs of one of the generated runs (replace the name with
#     the one returned in step 11)
kubectl logs job/minute-report-cronjob-<suffix>

# 13. Clean up the lab's resources
kubectl delete -f manifests/

# 14. Delete the cluster
kind delete cluster --name k8s-labs
```

## Points to understand

* **Why can't a Job use `restartPolicy: Always`?**
  Because "Always" means "restart forever", which would prevent the Job
  from ever reaching the `Complete` state — the very notion of completion
  wouldn't make sense.

* **What happens if `parallelism` is greater than the remaining
  `completions`?** Kubernetes never starts more Pods than needed to reach
  `completions`; the last batch is scaled down accordingly.

* **Why `concurrencyPolicy: Forbid` rather than `Allow` here?**
  For a report generated every minute, there's no benefit to having two
  overlapping runs — `Forbid` guarantees only one runs at a time, which is
  the safest default for most scheduled tasks.

* **What happens if the cluster is stopped for a while and then restarted?**
  The `CronJob` controller doesn't catch up indefinitely on missed runs;
  `startingDeadlineSeconds` defines the tolerance window beyond which a
  missed run is simply skipped.

## Useful links

* [Kubernetes docs — Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
* [Kubernetes docs — CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
* [Cron schedule syntax](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/#cron-schedule-syntax)
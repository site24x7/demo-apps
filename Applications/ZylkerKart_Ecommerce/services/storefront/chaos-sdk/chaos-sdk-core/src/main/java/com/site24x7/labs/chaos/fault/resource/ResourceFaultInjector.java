package com.site24x7.labs.chaos.fault.resource;

import com.site24x7.labs.chaos.config.FaultRuleConfig;
import com.site24x7.labs.chaos.engine.ChaosEngine;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.File;
import java.io.FileOutputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.locks.ReentrantLock;

/**
 * Evaluates resource exhaustion fault rules and injects faults via background threads.
 * <p>
 * Fault types handled:
 * - thread_pool_exhaustion: spawns busy-wait threads to consume thread pool capacity
 * - memory_pressure: allocates large byte arrays to consume heap memory
 * - cpu_burn: spawns threads that perform tight computation loops to burn CPU
 * - gc_pressure: rapidly allocates and discards objects to trigger frequent GC pauses
 * - thread_deadlock: creates two threads that deadlock on ReentrantLocks
 * - disk_fill: writes temp files to consume disk space
 * <p>
 * All resource faults are time-bounded with configurable duration.
 * Background threads are daemon threads so they won't prevent JVM shutdown.
 */
public class ResourceFaultInjector {

    private static final Logger log = LoggerFactory.getLogger(ResourceFaultInjector.class);

    private final ChaosEngine engine;
    private final AtomicBoolean resourceFaultActive = new AtomicBoolean(false);

    public ResourceFaultInjector(ChaosEngine engine) {
        this.engine = engine;
    }

    /**
     * Check for active resource fault rules and execute them.
     * Called periodically by the config watcher or on config update.
     * Only one resource fault can be active at a time to prevent cascading failures.
     */
    public void evaluateAndApply() {
        if (!engine.isEnabled()) {
            return;
        }

        // Prevent overlapping resource faults
        if (resourceFaultActive.get()) {
            log.debug("Resource fault already active, skipping");
            return;
        }

        List<FaultRuleConfig> rules = engine.getActiveRules().stream()
                .filter(r -> isResourceFaultType(r.getFaultType()))
                .filter(engine::shouldFire)
                .toList();

        if (rules.isEmpty()) {
            return;
        }

        // Execute the first matching rule
        FaultRuleConfig rule = rules.get(0);
        switch (rule.getFaultType()) {
            case "thread_pool_exhaustion" -> applyThreadPoolExhaustion(rule);
            case "memory_pressure" -> applyMemoryPressure(rule);
            case "cpu_burn" -> applyCpuBurn(rule);
            case "gc_pressure" -> applyGcPressure(rule);
            case "thread_deadlock" -> applyThreadDeadlock(rule);
            case "disk_fill" -> applyDiskFill(rule);
            default -> log.warn("Unknown resource fault type: {}", rule.getFaultType());
        }
    }

    private boolean isResourceFaultType(String faultType) {
        return "thread_pool_exhaustion".equals(faultType)
                || "memory_pressure".equals(faultType)
                || "cpu_burn".equals(faultType)
                || "gc_pressure".equals(faultType)
                || "thread_deadlock".equals(faultType)
                || "disk_fill".equals(faultType);
    }

    private void applyThreadPoolExhaustion(FaultRuleConfig rule) {
        Map<String, Object> config = rule.getConfig();
        int threadCount = getConfigInt(config, "thread_count", 10);
        long durationMs = getConfigLong(config, "duration_ms", 30000);

        // Enforce safety limits
        threadCount = Math.min(Math.max(threadCount, 1), 50);
        durationMs = Math.min(Math.max(durationMs, 1000), 60000);

        log.info("Injecting thread pool exhaustion: {} threads for {}ms", threadCount, durationMs);

        if (!resourceFaultActive.compareAndSet(false, true)) {
            return;
        }

        final int tc = threadCount;
        final long dm = durationMs;
        Thread orchestrator = new Thread(() -> {
            try {
                CountDownLatch latch = new CountDownLatch(tc);
                List<Thread> threads = new ArrayList<>();
                for (int i = 0; i < tc; i++) {
                    Thread t = new Thread(() -> {
                        try {
                            Thread.sleep(dm);
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                        } finally {
                            latch.countDown();
                        }
                    }, "chaos-thread-exhaust-" + i);
                    t.setDaemon(true);
                    threads.add(t);
                    t.start();
                }
                latch.await(dm + 5000, TimeUnit.MILLISECONDS);
                log.info("Thread pool exhaustion fault completed");
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            } finally {
                resourceFaultActive.set(false);
            }
        }, "chaos-thread-exhaust-orchestrator");
        orchestrator.setDaemon(true);
        orchestrator.start();
    }

    @SuppressWarnings("unused")
    private void applyMemoryPressure(FaultRuleConfig rule) {
        Map<String, Object> config = rule.getConfig();
        int allocationMb = getConfigInt(config, "allocation_mb", 64);
        long durationMs = getConfigLong(config, "duration_ms", 30000);

        // Enforce safety limits
        allocationMb = Math.min(Math.max(allocationMb, 1), 512);
        durationMs = Math.min(Math.max(durationMs, 1000), 60000);

        log.info("Injecting memory pressure: {}MB for {}ms", allocationMb, durationMs);

        if (!resourceFaultActive.compareAndSet(false, true)) {
            return;
        }

        final int mb = allocationMb;
        final long dm = durationMs;
        Thread memThread = new Thread(() -> {
            byte[][] blocks = null;
            try {
                // Allocate memory in 1MB blocks
                blocks = new byte[mb][];
                for (int i = 0; i < mb; i++) {
                    blocks[i] = new byte[1024 * 1024]; // 1MB each
                    // Touch the memory to ensure it's actually allocated (not just virtual)
                    for (int j = 0; j < blocks[i].length; j += 4096) {
                        blocks[i][j] = (byte) i;
                    }
                }
                log.debug("Memory pressure: allocated {}MB", mb);
                Thread.sleep(dm);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            } catch (OutOfMemoryError e) {
                log.warn("Memory pressure: OOM during allocation (allocated partial), holding for duration");
                try {
                    Thread.sleep(dm);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                }
            } finally {
                // Release references so GC can reclaim
                blocks = null;
                System.gc(); // Hint to GC
                resourceFaultActive.set(false);
                log.info("Memory pressure fault completed, memory released");
            }
        }, "chaos-memory-pressure");
        memThread.setDaemon(true);
        memThread.start();
    }

    private void applyCpuBurn(FaultRuleConfig rule) {
        Map<String, Object> config = rule.getConfig();
        int threadCount = getConfigInt(config, "thread_count", 2);
        long durationMs = getConfigLong(config, "duration_ms", 30000);

        // Enforce safety limits
        threadCount = Math.min(Math.max(threadCount, 1), 8);
        durationMs = Math.min(Math.max(durationMs, 1000), 60000);

        log.info("Injecting CPU burn: {} threads for {}ms", threadCount, durationMs);

        if (!resourceFaultActive.compareAndSet(false, true)) {
            return;
        }

        final int tc = threadCount;
        final long dm = durationMs;
        Thread orchestrator = new Thread(() -> {
            try {
                CountDownLatch latch = new CountDownLatch(tc);
                long endTime = System.currentTimeMillis() + dm;
                List<Thread> threads = new ArrayList<>();
                for (int i = 0; i < tc; i++) {
                    Thread t = new Thread(() -> {
                        try {
                            // Tight loop that burns CPU
                            while (System.currentTimeMillis() < endTime && !Thread.currentThread().isInterrupted()) {
                                // Perform computation to burn CPU (not just busy-wait)
                                double x = Math.random();
                                for (int j = 0; j < 1000; j++) {
                                    x = Math.sin(x) * Math.cos(x);
                                }
                            }
                        } finally {
                            latch.countDown();
                        }
                    }, "chaos-cpu-burn-" + i);
                    t.setDaemon(true);
                    threads.add(t);
                    t.start();
                }
                latch.await(dm + 5000, TimeUnit.MILLISECONDS);
                log.info("CPU burn fault completed");
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            } finally {
                resourceFaultActive.set(false);
            }
        }, "chaos-cpu-burn-orchestrator");
        orchestrator.setDaemon(true);
        orchestrator.start();
    }

    @SuppressWarnings("unused")
    private void applyGcPressure(FaultRuleConfig rule) {
        Map<String, Object> config = rule.getConfig();
        int allocRateMbPerSec = getConfigInt(config, "allocation_rate_mb_per_sec", 10);
        long durationMs = getConfigLong(config, "duration_ms", 30000);

        // Enforce safety limits
        allocRateMbPerSec = Math.min(Math.max(allocRateMbPerSec, 1), 100);
        durationMs = Math.min(Math.max(durationMs, 1000), 60000);

        log.info("Injecting GC pressure: {}MB/sec for {}ms", allocRateMbPerSec, durationMs);

        if (!resourceFaultActive.compareAndSet(false, true)) {
            return;
        }

        final int rate = allocRateMbPerSec;
        final long dm = durationMs;
        Thread gcThread = new Thread(() -> {
            try {
                long endTime = System.currentTimeMillis() + dm;
                // Calculate sleep interval to achieve desired rate
                // Allocate 1MB at a time, sleep (1000/rate) ms between allocations
                long sleepMs = Math.max(1, 1000 / rate);
                while (System.currentTimeMillis() < endTime && !Thread.currentThread().isInterrupted()) {
                    // Allocate 1MB — short-lived reference so GC must collect it
                    byte[] garbage = new byte[1024 * 1024];
                    // Touch it to ensure actual allocation
                    garbage[0] = 1;
                    garbage[garbage.length - 1] = 1;
                    // Immediately discard reference (garbage becomes eligible for GC)
                    garbage = null;
                    Thread.sleep(sleepMs);
                }
                log.info("GC pressure fault completed");
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            } catch (OutOfMemoryError e) {
                log.warn("GC pressure: OOM during allocation, stopping early");
            } finally {
                resourceFaultActive.set(false);
            }
        }, "chaos-gc-pressure");
        gcThread.setDaemon(true);
        gcThread.start();
    }

    private void applyThreadDeadlock(FaultRuleConfig rule) {
        Map<String, Object> config = rule.getConfig();
        long durationMs = getConfigLong(config, "duration_ms", 30000);

        // Enforce safety limits
        durationMs = Math.min(Math.max(durationMs, 1000), 60000);

        log.info("Injecting thread deadlock for {}ms", durationMs);

        if (!resourceFaultActive.compareAndSet(false, true)) {
            return;
        }

        final long dm = durationMs;
        final ReentrantLock lockA = new ReentrantLock();
        final ReentrantLock lockB = new ReentrantLock();

        // Thread 1: acquire A then B
        Thread t1 = new Thread(() -> {
            lockA.lock();
            try {
                Thread.sleep(50); // Ensure both threads have their first lock
                lockB.lock(); // Will deadlock here
                try {
                    Thread.sleep(dm);
                } finally {
                    lockB.unlock();
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            } finally {
                lockA.unlock();
            }
        }, "chaos-deadlock-1");
        t1.setDaemon(true);

        // Thread 2: acquire B then A (opposite order — guaranteed deadlock)
        Thread t2 = new Thread(() -> {
            lockB.lock();
            try {
                Thread.sleep(50); // Ensure both threads have their first lock
                lockA.lock(); // Will deadlock here
                try {
                    Thread.sleep(dm);
                } finally {
                    lockA.unlock();
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            } finally {
                lockB.unlock();
            }
        }, "chaos-deadlock-2");
        t2.setDaemon(true);

        // Watchdog thread: waits for duration, then interrupts both deadlocked threads
        Thread watchdog = new Thread(() -> {
            try {
                t1.start();
                t2.start();
                Thread.sleep(dm);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            } finally {
                t1.interrupt();
                t2.interrupt();
                resourceFaultActive.set(false);
                log.info("Thread deadlock fault completed (threads interrupted)");
            }
        }, "chaos-deadlock-watchdog");
        watchdog.setDaemon(true);
        watchdog.start();
    }

    private void applyDiskFill(FaultRuleConfig rule) {
        Map<String, Object> config = rule.getConfig();
        int allocationMb = getConfigInt(config, "allocation_mb", 64);
        long durationMs = getConfigLong(config, "duration_ms", 30000);

        // Enforce safety limits
        allocationMb = Math.min(Math.max(allocationMb, 1), 512);
        durationMs = Math.min(Math.max(durationMs, 1000), 60000);

        log.info("Injecting disk fill: {}MB for {}ms", allocationMb, durationMs);

        if (!resourceFaultActive.compareAndSet(false, true)) {
            return;
        }

        final int mb = allocationMb;
        final long dm = durationMs;
        Thread diskThread = new Thread(() -> {
            List<File> tempFiles = new ArrayList<>();
            try {
                File tmpDir = new File(System.getProperty("java.io.tmpdir"));
                byte[] block = new byte[1024 * 1024]; // 1MB block
                java.util.Arrays.fill(block, (byte) 0xAA);

                for (int i = 0; i < mb; i++) {
                    File f = new File(tmpDir, "chaos-disk-fill-" + i + ".tmp");
                    f.deleteOnExit(); // Safety net
                    try (FileOutputStream fos = new FileOutputStream(f)) {
                        fos.write(block);
                    }
                    tempFiles.add(f);
                }
                log.debug("Disk fill: wrote {}MB of temp files", mb);

                // Hold the files for the specified duration
                Thread.sleep(dm);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            } catch (Exception e) {
                log.warn("Disk fill: error during file writing: {}", e.getMessage());
            } finally {
                // Clean up temp files
                for (File f : tempFiles) {
                    if (f.exists()) {
                        f.delete();
                    }
                }
                resourceFaultActive.set(false);
                log.info("Disk fill fault completed, {} temp files cleaned up", tempFiles.size());
            }
        }, "chaos-disk-fill");
        diskThread.setDaemon(true);
        diskThread.start();
    }

    private int getConfigInt(Map<String, Object> config, String key, int defaultValue) {
        if (config == null) return defaultValue;
        Object val = config.get(key);
        if (val instanceof Number) return ((Number) val).intValue();
        if (val instanceof String) {
            try { return Integer.parseInt((String) val); } catch (NumberFormatException e) { return defaultValue; }
        }
        return defaultValue;
    }

    private long getConfigLong(Map<String, Object> config, String key, long defaultValue) {
        if (config == null) return defaultValue;
        Object val = config.get(key);
        if (val instanceof Number) return ((Number) val).longValue();
        if (val instanceof String) {
            try { return Long.parseLong((String) val); } catch (NumberFormatException e) { return defaultValue; }
        }
        return defaultValue;
    }
}

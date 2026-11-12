// Odin procs run on the engine's WorkerThreadPool, without a Callable.
package godot

import "base:intrinsics"
import "base:runtime"
import gde "../gdextension"

// Runs `f(data)` once on one of the engine's worker threads and returns the task's id, which
// `wait_task` takes. `f` must be a compile-time constant proc taking `^D`.
//
// `f` runs off the main thread, in a context of its own: the core's allocator, and the worker
// thread's own temp allocator, rolled back when `f` returns. It must not touch what the main thread
// is changing, and every engine call it makes must be one the engine allows off the main thread.
// `data` must outlive the task: wait for it before freeing `data` or unloading.
run_task :: proc($f: $P, data: ^$D, high_priority := false, description := "") -> i64 where intrinsics.type_is_proc(P) {
	run :: proc "c" (userdata: rawptr) {
		// The core's context, with this worker thread's own temp arena in place of the main
		// thread's that `ctx` holds, marked and rolled back around the call.
		context = ctx
		t := worker_temp()
		context.temp_allocator.data = t
		temp := runtime.arena_temp_begin(&t.arena)
		defer runtime.arena_temp_end(temp)
		// Saved and restored: a worker waiting on another task may run it on this thread.
		when ODIN_DEBUG {
			was := in_task
			in_task = true
		}
		f((^D)(userdata))
		when ODIN_DEBUG { in_task = was }
	}
	return add_task(run, data, high_priority, description)
}

// Runs `f(data, i)` for every `i` in `0 ..< count`, spread over up to `tasks` worker threads (-1 for
// the engine's choice), and returns the group's id, which `wait_group` takes. Each `i` gets its
// own context and temp memory, as in `run_task`, whose rules apply. `f` is called once per index, so
// give it work in chunks rather than one tiny step each.
run_group :: proc($f: $P, data: ^$D, count: int, tasks := -1, high_priority := false, description := "") -> i64 where intrinsics.type_is_proc(P) {
	run :: proc "c" (userdata: rawptr, i: u32) {
		// The core's context, with this worker thread's own temp arena in place of the main
		// thread's that `ctx` holds, marked and rolled back around the call.
		context = ctx
		t := worker_temp()
		context.temp_allocator.data = t
		temp := runtime.arena_temp_begin(&t.arena)
		defer runtime.arena_temp_end(temp)
		// Saved and restored: a worker waiting on another task may run it on this thread.
		when ODIN_DEBUG {
			was := in_task
			in_task = true
		}
		f((^D)(userdata), int(i))
		when ODIN_DEBUG { in_task = was }
	}
	assert(count >= 0 && count <= int(max(i32)), "godot_odin: run_group count out of range")
	return add_group(run, data, count, tasks, high_priority, description)
}

// Waits until task `id` from `run_task` has finished.
wait_task :: proc "contextless" (id: i64) {
	worker_thread_pool_wait_for_task_completion(worker_thread_pool_singleton(), id)
}

// Waits until every call of group `id` from `run_group` has finished.
wait_group :: proc "contextless" (id: i64) {
	worker_thread_pool_wait_for_group_task_completion(worker_thread_pool_singleton(), id)
}

// This thread's own temp allocator data, which a worker call's context points at.
@(private)
worker_temp :: #force_inline proc "contextless" () -> ^runtime.Default_Temp_Allocator {
	return &runtime.global_default_temp_allocator_data
}

// Queues `run(data)` on the pool. The engine reads `description` before this returns.
@(private)
add_task :: proc "contextless" (run: gde.WorkerThreadPoolTask, data: rawptr, high_priority: bool, description: string) -> i64 {
	text := string_of(description)
	defer destroy[.STRING](&text)
	return gde.worker_thread_pool_add_native_task(gde.ObjectPtr(worker_thread_pool_singleton()), run, data, gde.Bool(high_priority), &text)
}

// Queues `run(data, i)` for every `i` in `0 ..< count` on the pool.
@(private)
add_group :: proc "contextless" (run: gde.WorkerThreadPoolGroupTask, data: rawptr, count, tasks: int, high_priority: bool, description: string) -> i64 {
	text := string_of(description)
	defer destroy[.STRING](&text)
	return gde.worker_thread_pool_add_native_group_task(gde.ObjectPtr(worker_thread_pool_singleton()), run, data, i32(count), i32(tasks), gde.Bool(high_priority), &text)
}

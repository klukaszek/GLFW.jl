module GLFW

using GLFW_jll

struct ThreadAssertionError
	target_thread::Int
	current_thread::Int
end

"""
	ThreadAssertionError(target_thread[, current_thread = Threads.threadid()])

The currently used thread is different from the `target_thread` that must be used.
"""
ThreadAssertionError(target) = ThreadAssertionError(target, Threads.threadid())

function Base.showerror(io::IO, e::ThreadAssertionError)
	print(io, "ThreadAssertionError: Code must run on thread $(e.target_thread) but ran on thread $(e.current_thread).")
end

const ENABLE_THREAD_ASSERTIONS = Ref(get(ENV, "GLFW_ENABLE_THREAD_ASSERTIONS", "true") == "true")

# The GLFW docs notes on most function that they should only be called from the main thread
function require_main_thread()
	if ENABLE_THREAD_ASSERTIONS[] && Threads.threadid() != 1
		throw(ThreadAssertionError(1))
	end
	return
end

macro require_main_thread(code)
	esc(quote
		require_main_thread()
		$code
	end)
end

function GetVersion()
	# any thread
	major, minor, rev = Ref{Cint}(), Ref{Cint}(), Ref{Cint}()
	ccall((:glfwGetVersion, libglfw), Cvoid, (Ref{Cint}, Ref{Cint}, Ref{Cint}), major, minor, rev)
	VersionNumber(major[], minor[], rev[])
end

include("callback.jl")
include("glfw3.jl")
include("vulkan.jl")
include("monitor_properties.jl")

const _init_errors = Exception[]

function _SetErrorCallbackPtr(callback::Ptr{Cvoid})
	require_main_thread()
	ccall((:glfwSetErrorCallback, libglfw), Ptr{Cvoid}, (Ptr{Cvoid},), callback)
	return nothing
end

function _RecordErrorCallback(code::Cint, description::Cstring)
	push!(_init_errors, GLFWError(code, unsafe_string(description)))
	return nothing
end

function _ThrowErrorCallback(code::Cint, description::Cstring)
	throw(GLFWError(code, unsafe_string(description)))
	return nothing
end

_record_error_callback_ptr() = @cfunction(_RecordErrorCallback, Cvoid, (Cint, Cstring))
_throw_error_callback_ptr() = @cfunction(_ThrowErrorCallback, Cvoid, (Cint, Cstring))

function __init__()
	# Save errors that occur during initialization
	empty!(_init_errors)
	_SetErrorCallbackPtr(_record_error_callback_ptr())

	try
		Init()
	catch err
		push!(_init_errors, err)
	finally
		_SetErrorCallbackPtr(_throw_error_callback_ptr())
	end

	if is_initialized()
		atexit(Terminate)
		for err in _init_errors
			@warn err  # Warn about any non-fatal errors that may have occurred during initialization
		end
	else
		throw(copy(_init_errors))  # Throw fatal errors
	end
end

end

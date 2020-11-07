# Default appearance options. Override in config.fish if you want.
if ! set -q glow_dirty_indicator
    set -g glow_dirty_indicator "•"
end

if ! set -q glow_fish_prompt
    set -g glow_fish_prompt "><,^>"
end

if ! set -q glow_prompt_suffix
    set -g glow_prompt_suffix '$'
end

# This should be set to be at least as long as glow_dirty_indicator, due to a fish bug
if ! set -q glow_clean_indicator
    set -g glow_clean_indicator (string replace -r -a '.' ' ' $glow_dirty_indicator)
end

if ! set -q glow_cwd_color
    set -g glow_cwd_color green
end

if ! set -q glow_git_color
    set -g glow_git_color blue
end

# State used for memoization and async calls.
set -g __glow_cmd_id 0
set -g __glow_git_state_cmd_id -1
set -g __glow_git_static ""
set -g __glow_dirty ""

# Increment a counter each time a prompt is about to be displayed.
# Enables us to distingish between redraw requests and new prompts.
function __glow_increment_cmd_id --on-event fish_prompt
    set __glow_cmd_id (math $__glow_cmd_id + 1)
end

# Abort an in-flight dirty check, if any.
function __glow_abort_check
    if set -q __glow_check_pid
        set -l pid $__glow_check_pid
        functions -e __glow_on_finish_$pid
        command kill $pid >/dev/null 2>&1
        set -e __glow_check_pid
    end
end

function __glow_git_status
    # Reset state if this call is *not* due to a redraw request
    set -l prev_dirty $__glow_dirty
    if test $__glow_cmd_id -ne $__glow_git_state_cmd_id
        __glow_abort_check

        set __glow_git_state_cmd_id $__glow_cmd_id
        set __glow_git_static ""
        set __glow_dirty ""
    end

    # Fetch git position & action synchronously.
    # Memoize results to avoid recomputation on subsequent redraws.
    if test -z $__glow_git_static
        # Determine git working directory
        set -l git_dir (command git --no-optional-locks rev-parse --absolute-git-dir 2>/dev/null)
        if test $status -ne 0
            return 1
        end

        set -l position (command git --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
        if test $status -ne 0
            # Denote detached HEAD state with short commit hash
            set position (command git --no-optional-locks rev-parse --short HEAD 2>/dev/null)
            if test $status -eq 0
                set position "@$position"
            end
        end

        # TODO: add bisect
        set -l action ""
        if test -f "$git_dir/MERGE_HEAD"
            set action "merge"
        else if test -d "$git_dir/rebase-merge"
            set branch "rebase"
        else if test -d "$git_dir/rebase-apply"
            set branch "rebase"
        end

        set -l state $position
        if test -n $action
            set state "$state <$action>"
        end

        set -g __glow_git_static $state
    end

    # Fetch dirty status asynchronously.
    if test -z $__glow_dirty
        if ! set -q __glow_check_pid
            # Compose shell command to run in background
            set -l check_cmd "git --no-optional-locks status -unormal --porcelain --ignore-submodules 2>/dev/null | head -n1 | count"
            set -l cmd "if test ($check_cmd) != "0"; exit 1; else; exit 0; end"

            begin
                # Defer execution of event handlers by fish for the remainder of lexical scope.
                # This is to prevent a race between the child process exiting before we can get set up.
                block -l

                set -g __glow_check_pid 0
                command fish --private --command "$cmd" >/dev/null 2>&1 &
                set -l pid (jobs --last --pid)

                set -g __glow_check_pid $pid

                # Use exit code to convey dirty status to parent process.
                function __glow_on_finish_$pid --inherit-variable pid --on-process-exit $pid
                    functions -e __glow_on_finish_$pid

                    if set -q __glow_check_pid
                        if test $pid -eq $__glow_check_pid
                            switch $argv[3]
                                case 0
                                    set -g __glow_dirty_state 0
                                    if status is-interactive
                                        commandline -f repaint
                                    end
                                case 1
                                    set -g __glow_dirty_state 1
                                    if status is-interactive
                                        commandline -f repaint
                                    end
                                case '*'
                                    set -g __glow_dirty_state 2
                                    if status is-interactive
                                        commandline -f repaint
                                    end
                            end
                        end
                    end
                end
            end
        end

        if set -q __glow_dirty_state
            switch $__glow_dirty_state
                case 0
                    set -g __glow_dirty $glow_clean_indicator
                case 1
                    set -g __glow_dirty $glow_dirty_indicator
                case 2
                    set -g __glow_dirty "<err>"
            end

            set -e __glow_check_pid
            set -e __glow_dirty_state
        end
    end

    # Render git status. When in-progress, use previous state to reduce flicker.
    set_color $glow_git_color
    echo -n $__glow_git_static ''

    if ! test -z $__glow_dirty
        echo -n $__glow_dirty
    else if ! test -z $prev_dirty
        set_color --dim $glow_git_color
        echo -n $prev_dirty
        set_color normal
    end

    set_color normal
end

function __glow_vi_indicator
    if [ $fish_key_bindings = "fish_vi_key_bindings" ]
        switch $fish_bind_mode
            case "insert"
                set_color green
            case "default"
                set_color blue
            case "visual"
                set_color red
        end
		echo -n "$glow_fish_prompt "
        set_color normal
    end
end

# Suppress default mode prompt
function fish_mode_prompt
end

function fish_prompt
    set -l cwd (prompt_pwd)

    echo ''
    set_color $glow_cwd_color
    echo -sn $cwd
    set_color normal

    if test $cwd != '~'
        set -l git_state (__glow_git_status)
        if test $status -eq 0
            echo -sn " on $git_state"
        end
    end

    echo ''
    __glow_vi_indicator
    echo -n "$glow_prompt_suffix "
end

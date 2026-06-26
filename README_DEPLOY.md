# Running the Nova5 Mandarin Picker on a vast.ai Server

This kit lets you run the picker **simulation** on a rented Linux server and watch
it (RViz) from your MacBook through a normal web browser — no robot required.

## What you're actually running

Your two scripts are the top of a ROS 2 stack:

```
 Gazebo / MoveIt mock hardware  ->  move_group (MoveIt2)  ->  server.py  ->  client.py
        (the "simulation")          (planning + IK/FK)       (09e2…py)      (a898…py)
```

The scripts only ever talk to **`move_group`**, so the lightest faithful
simulation is MoveIt2's **mock-hardware demo**: it spins up `move_group`, a
joint-trajectory controller, and RViz, and the arm moves in RViz exactly as it
would on hardware. Gazebo (physics) is optional and covered at the end.

Three things were missing from your folder and are supplied here:

| Missing piece | Provided by this kit |
|---|---|
| The Nova5 MoveIt2 config + robot model | cloned from `Dobot-Arm/DOBOT_6Axis_ROS2_V4` (branch `feature/v4-optimization`) by `setup.sh` |
| `dobot_interfaces/action/ServoControl` (the gripper action — **not** in any official Dobot repo; it's custom to your project) | `deploy/dobot_interfaces/` + `deploy/fake_servo_server.py` |
| A camera/vision detector on `/realsense_detection_topic` | `deploy/fake_vision_publisher.py` (auto mode only) |

> The correct ROS 2 repo for Humble is `DOBOT_6Axis_ROS2_V4`. (`TCP-IP-ROS-6AXis`
> is ROS 1 and will not work on Humble.) The kit uses the right one.

## The networking rule (important)

ROS 2 discovery uses multicast, which **does not cross the internet/NAT**. So
**every ROS node runs on the server** and you stream only the *desktop* (pixels)
to your Mac over HTTP via noVNC. Don't try to run RViz on the Mac.

## Files in this kit (`deploy/`)

| File | Purpose |
|---|---|
| `env.sh` | shared environment (sourced by everything) |
| `setup.sh` | one-time: install ROS 2 Humble (if missing) + deps, clone Dobot pkgs, build workspace |
| `start-desktop.sh` | start the virtual desktop (TigerVNC + openbox + noVNC) |
| `run.sh` | launch sim + server + client in tmux |
| `stop.sh` | tear everything down |
| `fake_servo_server.py` | stand-in gripper action server |
| `fake_vision_publisher.py` | stand-in detector for auto mode |
| `dobot_interfaces/` | the custom `ServoControl` action package |
| `Dockerfile` | optional: bake a reusable image |

---

## Headless deploy (bare Ubuntu 22.04 on vast.ai → macOS over SSH tunnel)

"Headless" means: the server has no monitor and you never run a GUI locally —
all ROS nodes (including RViz) run **on the server**, and you view RViz as pixels
in your Mac's browser through noVNC. This uses an **SSH tunnel**, so it works
whether or not you exposed port 6080 when renting.

> This walkthrough is the **tested end-to-end path** — it bakes in every fix we
> hit the first time (SSH key injection, macOS `scp` quirks, the `set -u` ROS
> sourcing bug, the `needrestart` prompt, and the missing `vncpasswd` binary).
> Follow it top to bottom on a brand-new instance and it should just work.

### Step 0 — rent the instance (vast.ai)
- **Any Ubuntu 22.04 image works** — a plain/CLI image is fine. You do **not**
  need a "desktop" image: this kit installs its own virtual desktop (Xvnc +
  openbox + noVNC), and you view it in your browser regardless. A desktop image
  just wastes disk.
- A GPU is **not required** (RViz renders with Mesa software GL). ~24 GB RAM /
  a few CPUs is plenty.
- **Add your Mac's SSH key to the instance.** In the instance's "SSH Keys"
  dialog, paste the contents of `~/.ssh/id_ed25519.pub` (run `cat
  ~/.ssh/id_ed25519.pub` on your Mac). Keys are injected when the container
  **starts** — if you add the key to an already-running instance, **reboot it
  (↻)** so the key takes effect (otherwise you'll get `Permission denied
  (publickey)` below).
- From the instance card, copy the **"Direct ssh connect"** string. It looks
  like `ssh -p 31629 root@120.238.149.205`. Your **port** and **host** differ
  every time — substitute them everywhere below (shown here as `<PORT>` and
  `<HOST>`).

### Step 1 — copy the project to the server (run on your Mac)
`ssh` only *logs in*; it does **not** copy files. You must push the project
first. Use **`rsync`** — plain macOS `scp` is unreliable here (`scp -O ... .`
errors with `unexpected filename: .`, and iCloud-synced Desktop files can throw
`Operation canceled`). From this project folder on your Mac:
```bash
cd ~/Desktop/nova5_mandarin_picker
rsync -avz --exclude '.git' --exclude '*.png' \
  -e "ssh -i ~/.ssh/id_ed25519 -p <PORT>" \
  ./ root@<HOST>:/root/nova5_mandarin_picker/
```
Verify it landed (next step, after logging in): `ls /root/nova5_mandarin_picker`
should show `09e2…py`, `a898…py`, and `deploy/`.

### Step 2 — SSH in with a tunnel for the browser desktop
This forwards the server's noVNC port (6080) to your Mac's localhost. **Use
6080** (not vast's default 8080) — that's the port the kit serves:
```bash
ssh -i ~/.ssh/id_ed25519 -p <PORT> -L 6080:localhost:6080 root@<HOST>
```
Keep this terminal open — the tunnel lives as long as the SSH session does. You
can run all the server-side steps below in this same window.

### Step 3 — install + build (on the server, ~15–25 min the first time)
```bash
cd /root/nova5_mandarin_picker
bash deploy/setup.sh
```
This installs ROS 2 Humble, MoveIt, the VNC stack, clones the Nova5 packages,
builds your custom `dobot_interfaces`, and compiles the workspace. Two things
you'll see that are **normal / safe to ignore**:
- A blue **"Daemons using outdated libraries / which services should be
  restarted?"** dialog (`needrestart`). Press **Tab** to `<Ok>`, then **Enter**
  (leave the defaults). If asked "restart services without asking?", choose
  **Yes** so it stops interrupting.
- A red line `Unable to locate package ros-humble-warehouse-ros-mongo` — an
  optional MoveIt DB feature not published for Humble; the demo doesn't need it.

Wait for `>> Setup complete.` and confirm the final `colcon build` ends with
`Summary: N packages finished` and **no failures**. (If you ever see
`AMENT_TRACE_SETUP_FILES: unbound variable`, your `deploy/` copy is older than
these scripts — re-run Step 1 to re-sync; the current scripts fix it.)

### Step 4 — start the headless desktop (on the server)
```bash
VNC_PASSWORD=nova5vnc bash deploy/start-desktop.sh
```
This brings up Xvnc (display `:1`) + openbox + noVNC on port 6080. Ubuntu's
TigerVNC ships **no `vncpasswd` binary**, so the script generates the password
file itself with `openssl` — you should see `>> Desktop ready.` and, if you
check, `~/.vnc/passwd` is **8 bytes** (not 0). Then test the browser *before*
launching the sim:
- Open `http://localhost:6080/vnc.html`, click **Connect**, password
  **`nova5vnc`**.
- You should get a mostly **black screen with a taskbar** ("Desktop 1" + clock
  bottom corners). That black screen is success — it's an empty openbox desktop;
  RViz fills it in the next step.

### Step 5 — launch the simulation (on the server)
```bash
bash deploy/run.sh                 # add --vision for auto-pick mode
```
`run.sh` waits for `move_group`, then drops you into the **client** menu (tmux).
Within ~20–30s an **RViz** window with the Nova5 arm appears on the browser
desktop (it draws in slowly under software GL).

### Step 6 — drive it
In the client tmux window (prompt `指令 >`), type:
- `3` → go home (good first test; the arm moves in RViz)
- `1` then `400 0 300` → move tool to an XYZ point (mm)
- `q` → quit. Stop everything: `bash deploy/stop.sh`

tmux: detach `Ctrl-b` then `d`; switch windows `Ctrl-b` then `0`–`4`
(`0`=RViz/move_group logs, `2`=server, `4`=client).

### Notes
- **One window is enough.** The window you ran `run.sh` in holds the `-L 6080`
  tunnel *and* the client menu. Close any stray older SSH windows.
- **The SSH tunnel is the headless-friendly choice** — you don't need to have
  added `-p 6080:6080` when renting. If you *did* expose it, you can instead
  browse `http://<instance-ip>:<external-port>/vnc.html` (external port from the
  "IP & Port Info" popup) and skip the `-L` flag.
- **`tmux` keeps the sim alive if SSH drops.** Reconnect with the same
  `ssh -L ...` command, then `tmux attach -t nova5`.

---

## Auto (vision) mode

`bash deploy/run.sh --vision` also starts `fake_vision_publisher.py`, which feeds
a steady fake detection. In the client press `6` to enable auto mode; once 5
readings are stable the pick sequence runs (approach → close gripper → retreat →
twist → release → home), all visible in RViz.

The fake target is given in the **camera frame**; whether it's reachable depends
on the arm's pose, so IK may fail (the server logs it and aborts cleanly — no
crash). Tune it:
```bash
python3 deploy/fake_vision_publisher.py --ros-args -p cam_z_mm:=300 -p width_px:=80
```
(`width_px`/`height_px` ≥ 60 ⇒ "large orange" ⇒ release bin #2.) For guaranteed
motion, the manual menu (`1`,`3`,`5`) is the reliable demo.

---

## Full Gazebo physics (`run-gazebo.sh`)

The mock demo (`run.sh`) has no physics. For a real **Gazebo physics** sim, use
`run-gazebo.sh` — it's the Gazebo counterpart to `run.sh` and was tested
end-to-end (arm executes `go_home` under physics: `Goal reached, success!`).

```bash
bash deploy/stop.sh          # clear any running session first
bash deploy/run-gazebo.sh    # headless Gazebo (gzserver) + move_group + RViz + server + client
#   add --gui to also open the heavy Gazebo window (slow on software GL)
```

It launches a `nova5gz` tmux session with 5 windows, gated in order:
`gazebo` (physics + robot + `ros2_control` controllers) → `moveit` (move_group +
RViz, `use_sim_time`) → `servo` → `server` → `client`. View in the browser the
same way (`http://localhost:6080/vnc.html`) and drive from the client menu
(`3` = home, `1` = XYZ). Stop with `bash deploy/stop.sh`.

How the two launch files combine (their names are confusingly swapped):
- `dobot_gazebo/gazebo_moveit.launch.py` = Gazebo + robot spawn + controllers
  (no move_group, no RViz). Pulls in `gazebo_ros/gazebo.launch.py`.
- `nova5_moveit/moveit_gazebo.launch.py` = move_group + RViz (`use_sim_time:=True`).

Requirements baked into the kit (don't need manual steps anymore):
- `setup.sh` installs **`ros-humble-gazebo-ros2-control`** and builds
  **`dobot_gazebo`** (which drags in `cra_description`) — both were missing from
  the original "mock-only" build and caused `Package 'dobot_gazebo' not found`.
- The wait-loops use `ros2 ... --no-daemon` because the ROS 2 daemon can go
  stale (return an empty graph) after `daemon stop`, which otherwise hangs the
  `moveit`/`server` windows forever even though Gazebo is up. If you ever see a
  window stuck on "waiting for /clock" while `gzserver` is clearly running:
  `ros2 daemon stop` and it will recover.

Caveats: headless by default (no `gzclient`) because software GL makes the
Gazebo GUI near-unusable; the stock world has **no camera**, so auto/vision mode
(`client [6]`) has no detections here — use the manual menu. A harmless RViz
warning `transform is to frame 'dummy_link', but frame 'world' was expected`
appears but does not block motion.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Permission denied (publickey)` on ssh/rsync | The instance hasn't picked up your key. Confirm `~/.ssh/id_ed25519.pub` is in the instance's SSH-keys dialog, then **reboot the instance (↻)** — keys are injected at container start, not live. |
| `scp: error: unexpected filename: .` | `scp -O` chokes on `.` as source. Use the **`rsync`** command in Step 1 instead (or `scp ./*`). |
| `scp: ... Operation canceled` (macOS) | macOS scp + iCloud-evicted Desktop files. Use **`rsync`** (Step 1); if it persists, materialize the files first: `find . -type f -exec cat {} + >/dev/null`. |
| `AMENT_TRACE_SETUP_FILES: unbound variable` | A script ran with `set -u` while sourcing ROS. The current `env.sh`/`setup.sh` guard against this — re-run **Step 1** to re-sync an up-to-date `deploy/`. |
| `needrestart` blue dialog during `setup.sh` | Normal. **Tab** to `<Ok>`, **Enter**. Optionally answer **Yes** to "restart without asking". |
| `Unable to locate package ros-humble-warehouse-ros-mongo` | Harmless — optional MoveIt DB feature, not published for Humble; the demo doesn't use it. |
| Browser: `Authentication failure: No password configured for VNC Auth`, or VNC password rejected | Ubuntu's TigerVNC has no `vncpasswd`, so the password file may be 0 bytes. Re-run `VNC_PASSWORD=nova5vnc bash deploy/start-desktop.sh` (it now builds `~/.vnc/passwd` via openssl); confirm `ls -l ~/.vnc/passwd` shows **8 bytes**. |
| Browser can't connect to `localhost:6080` | Make sure the `ssh -L 6080:localhost:6080 ...` session (Step 2) is still open, and that `start-desktop.sh` ran without error. |
| Connected but **black screen** with just a taskbar | That's a working but empty desktop — RViz isn't running yet. Run `bash deploy/run.sh` (Step 5); RViz appears in ~20–30s. |
| `Package 'dobot_gazebo' not found` (running `run-gazebo.sh`) | The Gazebo package wasn't built. Re-run **Step 1** to re-sync `deploy/`, then `apt-get install -y ros-humble-gazebo-ros2-control` and `cd ~/dobot_ws && colcon build --packages-up-to dobot_gazebo`. The current `setup.sh` does both automatically. |
| Gazebo window stuck on `waiting for /clock` while `gzserver` is running | Stale ROS 2 daemon (returns an empty graph). The current scripts gate with `--no-daemon` to avoid it; to recover a live session run `ros2 daemon stop`. |
| RViz runs but only **~5 FPS** | Expected with software GL (no GPU). It's a display-only limit, not a robot/planning problem. Speed it up: lower the noVNC quality, shrink the desktop (`VNC_GEOMETRY=1280x720`), and in RViz drop the update rate / hide MotionPlanning's "Trail". See the FPS note below. |
| RViz window blank / GL errors | Ensure `LIBGL_ALWAYS_SOFTWARE=1` (set by `env.sh`); restart `start-desktop.sh`. |
| Server logs "未能连接到 /move_action" | `move_group` wasn't up yet — check the `moveit` tmux window finished loading, then restart the server window. |
| `colcon build` fails on a C++ Dobot package | `setup.sh` only builds `--packages-up-to nova5_moveit dobot_interfaces` on purpose; don't run a bare `colcon build` (it tries the TCP/IP driver packages the sim doesn't need). |
| RViz shows no robot model | the model lives in `dobot_rviz` (built automatically by the `--packages-up-to nova5_moveit` step); if needed, rebuild it: `cd ~/dobot_ws && colcon build --packages-select dobot_rviz && source install/setup.bash`. |
| `ModuleNotFoundError: dobot_interfaces` / `tf_transformations` | re-source: `source ~/dobot_ws/install/setup.bash`; confirm `setup.sh` finished its build step. |

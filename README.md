# ttyd-debug action

Composite action: start ttyd (attached to tmux) and ngrok on the runner. No service container; static binaries only (ttyd, tmux, ngrok).


[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)]([https://www.buymeacoffee.com/gbraad](https://buymeacoffee.com/hradaideh))


## Inputs

| Input | Required | Default | Description |
|-------|----------|--------|--------------|
| `ngrok_authtoken` | Yes | - | ngrok authtoken (use `secrets.NGROK_AUTHTOKEN`) |
| `port` | No | `7681` | Port for ttyd |
| `ngrok_domain` | No | `''` | Optional ngrok reserved domain |
| `username` | No | `debug` | Basic auth username (used only if `password` is set) |
| `password` | No | `''` | Basic auth password (e.g. `secrets.DEBUG_SESSION_PASSWORD`). If set, ttyd requires login before showing the terminal. |

## Security (optional basic auth)

To protect the debug URL with a simple login, set a repo secret `DEBUG_SESSION_PASSWORD` and pass it as the `password` input. The workflow will then require username/password (browser prompt) before opening the terminal. The username defaults to `debug`; override with the `username` input. Never log or echo the password.

## Finishing the workflow

The step waits until the file `/tmp/terminate_debugging` exists. In the browser terminal (tmux session), run:

```bash
touch /tmp/terminate_debugging
```

The action then exits and the workflow continues.

## Usage

```yaml
steps:
  - uses: ./.github/actions/ttyd-debug
    with:
      ngrok_authtoken: ${{ secrets.NGROK_AUTHTOKEN }}
      # Optional: require login (set repo secret DEBUG_SESSION_PASSWORD)
      password: ${{ secrets.DEBUG_SESSION_PASSWORD }}
      # username: debug   # default
```

Requires repo secret `NGROK_AUTHTOKEN`. Optional: `DEBUG_SESSION_PASSWORD` for basic auth. Linux only (ubuntu-latest; x86_64 and aarch64 supported).

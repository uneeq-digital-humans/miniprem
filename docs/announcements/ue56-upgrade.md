# MiniPrem Upgrade Instructions

> **Version 5.6mha • September 2025**

Follow these simple steps to upgrade your MiniPrem installation to version 5.6mha

<div class="alert-box alert-info">
<svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
</svg>
<div>
<strong>Important:</strong> This upgrade includes important improvements to speech processing, removes deprecated audio2face components, and requires Nvidia driver version 580.
</div>
</div>

---

## <div class="step-container"><div class="step-number">1</div><div class="step-content">Install Nvidia Driver Version 580</div></div>

Before upgrading MiniPrem, you must install the latest Nvidia driver version 580 on your Ubuntu system.

<div class="alert-box alert-error">
<svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"></path>
</svg>
<div>
<strong>Critical:</strong> This step must be completed before starting Docker containers. A system reboot is required after driver installation.
</div>
</div>

### Step 1.1: Check Available Drivers

For Desktop systems:
```bash
sudo ubuntu-drivers list
```

For Server systems:
```bash
sudo ubuntu-drivers list --gpgpu
```

You should see output similar to:
```
nvidia-driver-470
nvidia-driver-535
nvidia-driver-550
nvidia-driver-580     # ← This is what we want
nvidia-driver-580-open
```

### Step 1.2: Install Nvidia Driver 580

Install the specific driver version 580:
```bash
sudo ubuntu-drivers install nvidia-driver-580
```

<div class="alert-box alert-warning">
<svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"></path>
</svg>
<div>
<strong>Alternative:</strong> If version 580 is not available, use <code>sudo ubuntu-drivers install</code> to automatically install the latest compatible driver.
</div>
</div>

### Step 1.3: Reboot Your System

Reboot the system to load the new driver:
```bash
sudo reboot
```

### Step 1.4: Verify Installation

After reboot, confirm the driver version:
```bash
nvidia-smi
```

<div class="alert-box alert-success">
<svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
</svg>
<div>
<strong>Expected Output:</strong> You should see driver version 580.xx displayed in the top-left of the nvidia-smi output.
<pre class="code-block">
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 580.13.xx   Driver Version: 580.13.xx   CUDA Version: 12.x |
</pre>
</div>
</div>

---

## <div class="step-container"><div class="step-number">2</div><div class="step-content">Update Docker Image Version</div></div>

Locate and edit your `docker-compose.yml` or `docker-compose.default.yml` file.

### Find the image property and update it:

❌ **Old version:**
```yaml
image: facemeproduction/renny:previous-version
```

✅ **New version:**
```yaml
image: facemeproduction/renny:5.6mha
```

<div class="alert-box alert-warning">
<svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"></path>
</svg>
<div>
<strong>Important:</strong> Make sure to update the exact image line in your docker-compose file. The image property is typically under the main service definition.
</div>
</div>

---

## <div class="step-container"><div class="step-number">3</div><div class="step-content">Add New Environment Variable</div></div>

Edit your `docker-compose.env` or `docker-compose.default.env` file.

### Add this new environment variable:
```bash
NEW_SPEECH_OVERRIDE=1
```

<div class="alert-box alert-success">
<svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
</svg>
<div>
<strong>Tip:</strong> Add this variable at the end of your environment file for easy reference.
</div>
</div>

---

## <div class="step-container"><div class="step-number">4</div><div class="step-content">Remove Audio2Face Components</div></div>

Remove or comment out the deprecated audio2face sections from your docker-compose file.

### Option 1: Comment Out (Recommended)

Add `#` at the beginning of each line:
```yaml
# audio2face_with_emotion:
#   image: your-image-here
#   container_name: audio2face_emotion
#   ports:
#     - "8080:8080"
#   environment:
#     - ENV_VAR=value
#   networks:
#     - miniprem_network
#
# audio2face_controller:
#   image: your-controller-image
#   container_name: audio2face_ctrl
#   depends_on:
#     - audio2face_with_emotion
#   ports:
#     - "8081:8081"
#   networks:
#     - miniprem_network
```

### Option 2: Delete Entirely

Simply remove the entire sections from your docker-compose file:

<div class="alert-box alert-error">
<svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"></path>
</svg>
<div>
<strong>Remove these complete blocks:</strong><br>
• <code>audio2face_with_emotion:</code> and all its sub-properties<br>
• <code>audio2face_controller:</code> and all its sub-properties
</div>
</div>

<div class="alert-box alert-info">
<svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
</svg>
<div>
<strong>Note:</strong> Both methods achieve the same result. Commenting out is recommended as it allows you to easily revert changes if needed.
</div>
</div>

---

## <div class="step-container"><div class="step-number">5</div><div class="step-content">Restart Your Services</div></div>

Apply the changes by restarting your MiniPrem services.

### Run these commands:

1. **Stop current services:**
```bash
docker-compose down
```

2. **Pull new image:**
```bash
docker-compose pull
```

3. **Start services with new configuration:**
```bash
docker-compose up -d
```

---

## 🎉 Upgrade Complete!

Your MiniPrem installation is now running version 5.6mha with Nvidia driver 580 and enhanced speech processing.

### Need Help?

- **Support**: [support@digitalhumans.com](mailto:support@digitalhumans.com)
- **Website**: [digitalhumans.com](https://www.digitalhumans.com)
- **Documentation**: Browse our complete [MiniPrem documentation](../)

---

*© 2025 UneeQ Limited • MiniPrem v5.6mha Upgrade Guide*
## Update Package Lists
sudo apt purge *nvidia* *cuda*
sudo apt autoremove && sudo apt update

### Install Ubuntu Drivers
sudo ubuntu-drivers autoinstall
sudo apt install nvidia-cuda-toolkit
sudo reboot

## Post-Reboot Validation
sudo nvidia-smi -pm 1

### Confirm Successful Installation
nvidia-smi


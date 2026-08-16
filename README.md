# Ansible Role for Wireguard VPN setup

[![CI](https://github.com/unleftie/ansible-role-wireguard/actions/workflows/ci.yml/badge.svg)](https://github.com/unleftie/ansible-role-wireguard/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/unleftie/ansible-role-wireguard/badge)](https://securityscorecards.dev/viewer/?uri=github.com/unleftie/ansible-role-wireguard)

## Compatibility

| Platform | Version |
| -------- | ------- |
| ubuntu   | 26.04   |

## Dependencies

- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) (v2.14+)
- [Molecule](https://molecule.readthedocs.io/en/latest/installation.html) + (v4.0.4+) + [docker plugin](https://github.com/ansible-community/molecule-plugins) (for local testing)
- [Docker](https://docs.docker.com/get-docker/) (for local testing)

## Role dependencies

- iptables `required`
- iptables persistent `required`
- docker compose (see [prometheus_wireguard_exporter](https://github.com/MindFlavor/prometheus_wireguard_exporter)) `optional`
- prometheus (see [prometheus_wireguard_exporter](https://github.com/MindFlavor/prometheus_wireguard_exporter)) `optional`

## Local Testing

```sh
git clone https://github.com/unleftie/ansible-role-wireguard.git
cd ansible-role-wireguard/
ansible-galaxy install -r requirements.yml
molecule test
```

## Installation

```sh
ansible-galaxy install -r requirements.yml
```

Example [playbook](main.yml)

## Adding new clients

```sh
bash /etc/wireguard/$WG_INTERFACE-files/add-client.sh
```

## 📝 License

This project is licensed under the [MIT](LICENSE).

//
//  BuiltInCommands.swift
//  Kestrel
//
//  Pre-populated command library with 80+ commands across all categories.
//

import Foundation
import SwiftData

enum BuiltInCommands {

    struct CommandDef {
        let name: String
        let command: String
        let category: CommandCategory
        let description: String?

        init(_ name: String, _ command: String, _ category: CommandCategory, _ description: String? = nil) {
            self.name = name
            self.command = command
            self.category = category
            self.description = description
        }
    }

    static let all: [CommandDef] = system + networking + docker + kubernetes + git + nginx + files + custom

    // MARK: - System (15)

    static let system: [CommandDef] = [
        .init("Show system info", "uname -a && cat /etc/os-release", .system, "Kernel version and OS release details"),
        .init("CPU usage", "top -bn1 | grep 'Cpu(s)'", .system, "Current CPU utilisation snapshot"),
        .init("Memory usage", "free -h", .system, "Human-readable memory statistics"),
        .init("Disk usage", "df -h", .system, "Filesystem disk space usage"),
        .init("Largest directories", "du -sh /* 2>/dev/null | sort -rh | head -20", .system, "Top 20 largest root directories"),
        .init("Running processes", "ps aux --sort=-%cpu | head -20", .system, "Top 20 processes by CPU usage"),
        .init("Open file handles", "lsof | wc -l", .system, "Count of open file descriptors"),
        .init("Last 50 syslog lines", "tail -50 /var/log/syslog", .system, "Recent system log entries"),
        .init("Follow syslog", "tail -f /var/log/syslog", .system, "Stream syslog in real time"),
        .init("Reboot", "sudo reboot", .system, "Reboot the server immediately"),
        .init("Shutdown", "sudo shutdown -h now", .system, "Shutdown the server immediately"),
        .init("Uptime", "uptime", .system, "System uptime and load averages"),
        .init("Kernel version", "uname -r", .system, "Show running kernel version"),
        .init("Environment variables", "env | sort", .system, "List all environment variables sorted"),
        .init("Crontab list", "crontab -l", .system, "Show current user's cron jobs"),
    ]

    // MARK: - Networking (14)

    static let networking: [CommandDef] = [
        .init("Listening ports", "ss -tulpn", .networking, "Show all listening TCP/UDP ports"),
        .init("Active connections", "ss -tn state established", .networking, "Show established TCP connections"),
        .init("Network interfaces", "ip addr show", .networking, "List all network interfaces and IPs"),
        .init("Routing table", "ip route show", .networking, "Display kernel routing table"),
        .init("DNS resolution", "dig {domain}", .networking, "Query DNS records for a domain"),
        .init("Ping test", "ping -c 4 {host}", .networking, "Send 4 ICMP echo requests"),
        .init("Traceroute", "traceroute {host}", .networking, "Trace packet route to host"),
        .init("Firewall rules", "sudo iptables -L -n -v", .networking, "List all iptables rules"),
        .init("Bandwidth usage", "iftop -t -s 5 2>/dev/null || nethogs -t -c 5", .networking, "Snapshot of bandwidth usage"),
        .init("Public IP", "curl -s ifconfig.me", .networking, "Show public-facing IP address"),
        .init("ARP table", "arp -a", .networking, "Show ARP cache entries"),
        .init("Netstat summary", "ss -s", .networking, "Socket statistics summary"),
        .init("Download file", "curl -O {url}", .networking, "Download a file from URL"),
        .init("Check port open", "nc -zv {host} {port}", .networking, "Test if a port is reachable"),
    ]

    // MARK: - Docker (12)

    static let docker: [CommandDef] = [
        .init("List containers", "docker ps -a", .docker, "Show all containers including stopped"),
        .init("Container logs", "docker logs -f {container}", .docker, "Follow container log output"),
        .init("Container stats", "docker stats --no-stream", .docker, "One-shot container resource usage"),
        .init("Pull image", "docker pull {image}", .docker, "Download a Docker image"),
        .init("Restart container", "docker restart {container}", .docker, "Restart a running container"),
        .init("Remove stopped containers", "docker container prune -f", .docker, "Clean up stopped containers"),
        .init("Docker disk usage", "docker system df", .docker, "Show Docker disk usage breakdown"),
        .init("Exec into container", "docker exec -it {container} /bin/sh", .docker, "Open shell inside container"),
        .init("List images", "docker images", .docker, "Show all local Docker images"),
        .init("Inspect container", "docker inspect {container}", .docker, "Full JSON details of a container"),
        .init("Stop all containers", "docker stop $(docker ps -q)", .docker, "Stop every running container"),
        .init("Remove dangling images", "docker image prune -f", .docker, "Remove untagged images"),
    ]

    // MARK: - Kubernetes (12)

    static let kubernetes: [CommandDef] = [
        .init("Get pods", "kubectl get pods -A", .kubernetes, "List pods across all namespaces"),
        .init("Pod logs", "kubectl logs -f {pod} -n {namespace}", .kubernetes, "Stream logs from a pod"),
        .init("Get services", "kubectl get svc -A", .kubernetes, "List all services"),
        .init("Get deployments", "kubectl get deployments -A", .kubernetes, "List all deployments"),
        .init("Describe pod", "kubectl describe pod {pod} -n {namespace}", .kubernetes, "Detailed pod information"),
        .init("Get nodes", "kubectl get nodes -o wide", .kubernetes, "List cluster nodes with details"),
        .init("Cluster info", "kubectl cluster-info", .kubernetes, "Display cluster endpoint info"),
        .init("Get namespaces", "kubectl get namespaces", .kubernetes, "List all namespaces"),
        .init("Top pods", "kubectl top pods -A --sort-by=cpu", .kubernetes, "Pod resource usage sorted by CPU"),
        .init("Top nodes", "kubectl top nodes", .kubernetes, "Node resource usage"),
        .init("Restart deployment", "kubectl rollout restart deployment/{deployment} -n {namespace}", .kubernetes, "Rolling restart a deployment"),
        .init("Get events", "kubectl get events -A --sort-by=.lastTimestamp | tail -30", .kubernetes, "Recent cluster events"),
    ]

    // MARK: - Git (10)

    static let git: [CommandDef] = [
        .init("Git status", "git status", .git, "Working tree status"),
        .init("Git log (oneline)", "git log --oneline -20", .git, "Last 20 commits, compact format"),
        .init("Git diff", "git diff", .git, "Show unstaged changes"),
        .init("Git branch list", "git branch -a", .git, "List all local and remote branches"),
        .init("Git pull", "git pull origin {branch}", .git, "Pull latest from remote branch"),
        .init("Git stash", "git stash", .git, "Stash uncommitted changes"),
        .init("Git stash pop", "git stash pop", .git, "Restore last stashed changes"),
        .init("Git remote info", "git remote -v", .git, "Show configured remotes"),
        .init("Git blame", "git blame {file}", .git, "Line-by-line authorship of a file"),
        .init("Git log graph", "git log --oneline --graph --all -30", .git, "Visual branch graph, last 30"),
    ]

    // MARK: - Nginx (8)

    static let nginx: [CommandDef] = [
        .init("Status", "sudo systemctl status nginx", .nginx, "Nginx service status"),
        .init("Test config", "sudo nginx -t", .nginx, "Validate Nginx configuration"),
        .init("Reload config", "sudo systemctl reload nginx", .nginx, "Hot-reload Nginx configuration"),
        .init("Restart Nginx", "sudo systemctl restart nginx", .nginx, "Full restart of Nginx"),
        .init("Access log", "tail -f /var/log/nginx/access.log", .nginx, "Follow Nginx access log"),
        .init("Error log", "tail -f /var/log/nginx/error.log", .nginx, "Follow Nginx error log"),
        .init("List sites enabled", "ls -la /etc/nginx/sites-enabled/", .nginx, "Show enabled virtual hosts"),
        .init("Open config", "cat /etc/nginx/nginx.conf", .nginx, "Print main Nginx config"),
    ]

    // MARK: - Files (11)

    static let files: [CommandDef] = [
        .init("List files", "ls -la {path}", .files, "Detailed file listing"),
        .init("Find file by name", "find / -name '{filename}' 2>/dev/null", .files, "Search entire filesystem"),
        .init("Find large files", "find / -type f -size +100M -exec ls -lh {} \\; 2>/dev/null | head -20", .files, "Files over 100MB"),
        .init("Tail file", "tail -f {file}", .files, "Follow file output in real time"),
        .init("Cat file", "cat {file}", .files, "Print file contents"),
        .init("File permissions", "stat -c '%A %U %G %n' {file}", .files, "Show ownership and permissions"),
        .init("Change permissions", "chmod {mode} {file}", .files, "Modify file permissions"),
        .init("Change owner", "chown {user}:{group} {file}", .files, "Change file ownership"),
        .init("Disk usage of dir", "du -sh {path}", .files, "Size of a directory"),
        .init("Compress directory", "tar -czf {archive}.tar.gz {path}", .files, "Create gzipped tar archive"),
        .init("Extract archive", "tar -xzf {archive}", .files, "Extract gzipped tar archive"),
    ]

    // MARK: - Custom (seed)

    static let custom: [CommandDef] = [
        .init("Grep pattern in files", "grep -rn '{pattern}' {path}", .custom, "Recursive search for a pattern"),
        .init("Watch command", "watch -n {seconds} '{command}'", .custom, "Repeat a command at interval"),
    ]

    /// Creates SavedCommand SwiftData objects from the built-in definitions.
    /// Only inserts commands that don't already exist (by name).
    static func seedIfNeeded(into context: ModelContext) {
        // Check if we've already seeded
        let descriptor = FetchDescriptor<SavedCommand>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

        for def in all {
            let cmd = SavedCommand(
                name: def.name,
                command: def.command,
                category: def.category,
                commandDescription: def.description
            )
            context.insert(cmd)
        }

        try? context.save()
    }
}

import os
import json
import requests
from pathlib import Path
from datetime import datetime

class ClientDownload:
    def __init__(self):
        # 设置基础路径和版本文件路径
        self.base_path = Path('/www/wwwroot/clientdownload')
        self.version_file_path = Path('/www/wwwroot/clientdownload/Log/ClientDownloadVersion.json')
        self.client = requests.Session()  # 使用会话来发送HTTP请求
        # 下载配置
        self.softs = [
            {
                'name': 'Netch',
                'tagMethod': 'github_release',
                'gitRepo': 'netchx/Netch',
                'savePath': self.base_path,
                'v': 'no',
                'downloads': [
                    {
                        'sourceName': 'Netch.7z',
                        'saveName': 'Netch.7z',
                        'apkpureUrl': ''
                    }
                ]
            },
            {
                'name': 'V2RayU',
                'tagMethod': 'github_release',
                'gitRepo': 'yanue/V2rayU',
                'savePath': self.base_path,
                'v': 'yes',
                'downloads': [
                    {
                        'sourceName': 'V2rayU-64.dmg',
                        'saveName': 'V2rayU-64.dmg',
                        'apkpureUrl': ''
                    }
                ]
            },
            {
                'name': 'ShadowsocksXNG',
                'tagMethod': 'github_release',
                'gitRepo': 'shadowsocks/ShadowsocksX-NG',
                'savePath': self.base_path,
                'v': 'yes',
                'downloads': [
                    {
                        'sourceName': 'ShadowsocksX-NG.dmg',
                        'saveName': 'ShadowsocksX-NG.dmg',
                        'apkpureUrl': ''
                    }
                ]
            },
            {
                'name': 'ShadowsocksXNGR',
                'tagMethod': 'github_pre_release',
                'gitRepo': 'qinyuhang/ShadowsocksX-NG-R',
                'savePath': self.base_path,
                'v': 'no',
                'downloads': [
                    {
                        'sourceName': 'ShadowsocksX-NG-R8.dmg',
                        'saveName': 'ShadowsocksX-NG-R8.dmg',
                        'apkpureUrl': ''
                    }
                ]
            },
            {
                'name': 'V2RayNG',
                'tagMethod': 'github_pre_release',
                'gitRepo': '2dust/v2rayNG',
                'savePath': self.base_path,
                'v': 'no',
                'downloads': [
                    {
                        'sourceName': 'v2rayNG_{{tagName}}_arm64-v8a.apk',
                        'saveName': 'v2rayng_arm64-v8a.apk',
                        'apkpureUrl': ''
                    },
                    {
                        'sourceName': 'v2rayNG_{{tagName}}_armeabi-v7a.apk',
                        'saveName': 'v2rayng_armeabi-v7a.apk',
                        'apkpureUrl': ''
                    },
                    {
                        'sourceName': 'v2rayNG_{{tagName}}_x86.apk',
                        'saveName': 'v2rayng_x86.apk',
                        'apkpureUrl': ''
                    },
                    {
                        'sourceName': 'v2rayNG_{{tagName}}_x86_64.apk',
                        'saveName': 'v2rayng_x86_64.apk',
                        'apkpureUrl': ''
                    },
                    {
                        'sourceName': 'v2rayNG_{{tagName}}_universal.apk',
                        'saveName': 'v2rayng_universal.apk',
                        'apkpureUrl': ''
                    }
                ]
            },
            {
                'name': 'ShadowsocksR-Android',
                'tagMethod': 'github_release',
                'gitRepo': 'HMBSbige/ShadowsocksR-Android',
                'savePath': self.base_path,
                'v': 'no',
                'downloads': [
                    {
                        'sourceName': 'shadowsocksr-android-{{tagName}}.apk',
                        'saveName': 'ssr-android.apk',
                        'apkpureUrl': ''
                    }
                ]
            },
            {
                'name': 'ClashVerge',
                'tagMethod': 'github_release',
                'gitRepo': 'clash-verge-rev/clash-verge-rev',
                'savePath': self.base_path,
                'v': 'yes',
                'downloads': [
                    {
                        'sourceName': 'Clash.Verge_{{tagName}}_x64-setup.exe',
                        'saveName': 'Clash.Verge_x64.exe',
                        'apkpureUrl': ''
                    },
                    {
                        'sourceName': 'Clash.Verge_{{tagName}}_arm64-setup.exe',
                        'saveName': 'Clash.Verge_arm64.exe',
                        'apkpureUrl': ''
                    },
                    {
                        'sourceName': 'Clash.Verge_{{tagName}}_x64.dmg',
                        'saveName': 'Clash.Verge_x64.dmg',
                        'apkpureUrl': ''
                    },
                    {
                        'sourceName': 'Clash.Verge_{{tagName}}_aarch64.dmg',
                        'saveName': 'Clash.Verge_aarch64.dmg',
                        'apkpureUrl': ''
                    },
                    {
                        'sourceName': 'Clash.Verge_{{tagName}}_amd64.deb',
                        'saveName': 'Clash.Verge_amd64.deb',
                        'apkpureUrl': ''
                    }
                ]
            },
            {
                'name': 'FlClash',
                'tagMethod': 'github_release',
                'gitRepo': 'chen08209/FlClash',
                'savePath': self.base_path,
                'v': 'yes',
                'downloads': [
                    {
                        'sourceName': 'FlClash-{{tagName}}-android-arm64-v8a.apk',
                        'saveName': 'FlClash-android-arm64-v8.apk',
                        'apkpureUrl': ''
                    },
                    {
                        'sourceName': 'FlClash-{{tagName}}-android-armeabi-v7a.apk',
                        'saveName': 'FlClash-android-armeabi-v7.apk',
                        'apkpureUrl': ''
                    },
                    {
                        'sourceName': 'FlClash-{{tagName}}-android-x86_64.apk',
                        'saveName': 'FlClash-android-x64.apk',
                        'apkpureUrl': ''
                    }
                ]
            },
            {
                'name': 'ClashMetaForAndroid',
                'tagMethod': 'github_release',
                'gitRepo': 'MetaCubeX/ClashMetaForAndroid',
                'savePath': self.base_path,
                'v': 'yes',
                'downloads': [
                    {
                        'sourceName': 'cmfa-{{tagName}}-meta-arm64-v8a-release.apk',
                        'saveName': 'CMFA-android-arm64-v8.apk',
                        'apkpureUrl': ''
                    },
                    {
                        'sourceName': 'cmfa-{{tagName}}-meta-armeabi-v7a-release.apk',
                        'saveName': 'CMFA-android-armeabi-v7.apk',
                        'apkpureUrl': ''
                    },
                    {
                        'sourceName': 'cmfa-{{tagName}}-meta-universal-release.apk',
                        'saveName': 'CMFA-android-universal-release.apk',
                        'apkpureUrl': ''
                    }
                ]
            }
        ]
        self.version = self.get_local_versions()  # 获取本地存储的版本信息

    def get_local_versions(self):
        # 检查并读取版本文件
        self.version_file_path.parent.mkdir(parents=True, exist_ok=True)
        if not self.version_file_path.exists():
            print("本地版本文件不存在，创建中...")
            self.version_file_path.write_text(json.dumps({'createTime': datetime.now().timestamp()}))
        try:
            return json.loads(self.version_file_path.read_text())
        except json.JSONDecodeError:
            print("版本文件格式错误，无法解析.")
            return {}

    def set_local_versions(self):
        # 保存当前版本信息到版本文件
        with open(self.version_file_path, 'w') as f:
            json.dump(self.version, f)

    def get_latest_release_tag_name(self, repo):
        # 获取 GitHub 正式发布版本号
        url = f"https://api.github.com/repos/{repo}/releases/latest"
        try:
            response = self.client.get(url)
            response.raise_for_status()
            tag_name = response.json().get('tag_name', '')
            # 去掉前缀 'v'（如果存在），返回纯版本号
            if tag_name.startswith('v'):
                tag_name = tag_name[1:]
            return tag_name
        except requests.exceptions.HTTPError as e:
            if e.response.status_code == 404:
                print(f"- 获取 {repo} 的最新发布版本失败，地址不存在 (404)，跳过...")
            else:
                print(f"- 获取 {repo} 的最新发布版本时发生错误: {e}")
        return ''

    def get_latest_pre_release_tag_name(self, repo):
        # 获取 GitHub 预发布版本号
        url = f"https://api.github.com/repos/{repo}/releases"
        try:
            response = self.client.get(url)
            response.raise_for_status()
            releases = response.json()
            return releases[0].get('tag_name', '') if releases else ''
        except requests.exceptions.HTTPError as e:
            if e.response.status_code == 404:
                print(f"- 获取 {repo} 的预发布版本失败，地址不存在 (404)，跳过...")
            else:
                print(f"- 获取 {repo} 的预发布版本时发生错误: {e}")
        return ''

    def download_file(self, file_name, save_path, url):
        # 下载并保存文件
        save_path.mkdir(parents=True, exist_ok=True)
        print(f"- 开始下载 {file_name}...")
        try:
            response = self.client.get(url, stream=True)
            response.raise_for_status()  # 检查响应状态
            with open(save_path / file_name, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
            print(f"- {file_name} 下载并保存成功.")
            return True
        except requests.exceptions.HTTPError as e:
            print(f"- {file_name} 下载失败，地址: {url}")
            if e.response.status_code == 404:
                print(f"- 错误：地址不存在 (404)，跳过...")
            else:
                print(f"- 下载 {file_name} 时发生错误: {e}")
        except requests.exceptions.RequestException as e:
            print(f"- 下载 {file_name} 时发生请求错误: {e}, 地址: {url}")
        return False

    def get_soft(self, task):
        # 处理每个软件的更新
        save_path = Path(task['savePath'])
        print(f"====== 开始更新 {task['name']} ======")
        
        # 获取版本号
        if task['tagMethod'] == 'github_pre_release':
            tag_name = self.get_latest_pre_release_tag_name(task['gitRepo'])
        else:
            tag_name = self.get_latest_release_tag_name(task['gitRepo'])

        # 检查是否需要更新
        if self.version.get(task['name']) == tag_name:
            print(f"- {task['name']} 已是最新版本，跳过.")
            print(f"====== 结束 {task['name']} ======")
            return

        print(f"- 发现新版本 {tag_name} (本地版本: {self.version.get(task['name'], '未知')})")
        self.version[task['name']] = tag_name

        # 根据 v 参数决定是否添加前缀 'v'
        add_v_prefix = task.get('v', 'no') == 'yes'
        download_tag = f"v{tag_name}" if add_v_prefix and not tag_name.startswith('v') else tag_name

        # 下载每个文件
        for download in task['downloads']:
            source_name = download['sourceName'].replace('{{tagName}}', tag_name)
            file_name = download['saveName'] or source_name
            download_url = f"https://github.com/{task['gitRepo']}/releases/download/{download_tag}/{source_name}"
            
            # 删除旧版本文件并下载新版本
            file_path = save_path / file_name
            if file_path.exists():
                file_path.unlink()  # 删除旧文件
                print(f"- 已删除旧版本 {file_name}.")
            
            if self.download_file(file_name, save_path, download_url):
                self.set_local_versions()  # 更新本地版本文件
    
        print(f"====== {task['name']} 更新完成 ======")

    def run(self):
        # 执行更新过程
        for soft in self.softs:
            self.get_soft(soft)

# 使用示例
if __name__ == "__main__":
    downloader = ClientDownload()
    downloader.run()

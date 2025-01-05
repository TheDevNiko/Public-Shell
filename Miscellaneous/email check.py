import csv
import re
from dns import resolver
import socket
import smtplib
import ssl
import logging
import time
import pandas as pd
import sys
from datetime import datetime
import concurrent.futures

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

class EmailValidator:
    def __init__(self, timeout: int = 5):
        self.timeout = timeout
        self.basic_regex = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        self.smtp_ports = [25, 587, 465]  # 常用SMTP端口
        
        # 已知的有效域名列表
        self.valid_domains = {
            # 国际邮箱
            'gmail.com', 'outlook.com', 'hotmail.com', 'yahoo.com', 
            'icloud.com', 'protonmail.com', 'live.com', 'msn.com',
            
            # 中国邮箱
            'qq.com', '163.com', '126.com', 'sina.com', 'sohu.com',
            'yeah.net', 'foxmail.com', '139.com', 'aliyun.com', 
            '21cn.com', 'wo.cn', 'tom.com'
        }
        
        # DNS解析器配置
        self.resolver = resolver.Resolver()
        self.resolver.timeout = timeout
        self.resolver.lifetime = timeout
        self.resolver.nameservers = [
            '8.8.8.8',    # Google DNS
            '1.1.1.1',    # Cloudflare DNS
        ]
    
    def verify_dns(self, domain: str) -> tuple:
        """验证域名DNS记录"""
        try:
            mx_records = self.resolver.resolve(domain, 'MX')
            # 按优先级排序MX记录
            mx_list = sorted([(r.preference, str(r.exchange).rstrip('.')) 
                            for r in mx_records])
            return True, [mx for _, mx in mx_list]
        except Exception as e:
            return False, []

    def verify_smtp(self, mx_server: str) -> tuple:
        """验证SMTP连接，尝试多个端口"""
        error_messages = []
        
        for port in self.smtp_ports:
            try:
                if port == 465:
                    # SSL连接
                    context = ssl.create_default_context()
                    with smtplib.SMTP_SSL(mx_server, port, 
                                        timeout=self.timeout, 
                                        context=context) as smtp:
                        smtp.ehlo()
                        return True, f"SSL连接成功(端口{port})"
                else:
                    # 普通连接
                    with smtplib.SMTP(timeout=self.timeout) as smtp:
                        smtp.connect(mx_server, port=port)
                        smtp.ehlo()
                        
                        # 如果服务器支持STARTTLS，尝试升级到TLS
                        if port == 587:
                            try:
                                smtp.starttls()
                                smtp.ehlo()
                            except:
                                pass
                        
                        return True, f"连接成功(端口{port})"
                        
            except socket.timeout:
                error_messages.append(f"端口{port}超时")
            except ConnectionRefusedError:
                error_messages.append(f"端口{port}被拒绝")
            except ssl.SSLError:
                error_messages.append(f"端口{port} SSL错误")
            except Exception as e:
                error_messages.append(f"端口{port}错误: {str(e)}")
        
        return False, " | ".join(error_messages)

    def validate_email(self, email: str) -> dict:
        """验证单个邮箱"""
        result = {
            'email': email,
            'is_valid': False,
            'has_mx': False,
            'smtp_valid': False,
            'mx_records': [],
            'error_message': '',
            'smtp_details': '',
            'time_taken': 0,
            'validation_type': ''
        }
        
        start_time = time.time()
        
        try:
            # 基本检查
            if not email or pd.isna(email):
                result['error_message'] = '邮箱为空'
                return result
            
            email = str(email).strip().lower()
            
            # 格式验证
            if not re.match(self.basic_regex, email):
                result['error_message'] = '格式无效'
                return result
            
            # 获取域名
            domain = email.split('@')[1]
            
            # 检查是否是已知的有效域名
            if domain in self.valid_domains:
                result['is_valid'] = True
                result['has_mx'] = True
                result['smtp_valid'] = True
                result['validation_type'] = '已知域名'
                return result
            
            # 对未知域名进行完整验证
            result['validation_type'] = '完整验证'
            
            # 1. DNS验证
            has_mx, mx_records = self.verify_dns(domain)
            result['has_mx'] = has_mx
            result['mx_records'] = mx_records
            
            if not has_mx:
                result['error_message'] = '域名MX记录不存在'
                return result
            
            # 2. SMTP验证（尝试多个MX服务器）
            for mx_server in mx_records[:2]:  # 只尝试前两个MX服务器
                smtp_valid, smtp_details = self.verify_smtp(mx_server)
                if smtp_valid:
                    result['smtp_valid'] = True
                    result['smtp_details'] = smtp_details
                    result['is_valid'] = True
                    break
                else:
                    result['smtp_details'] = f"{mx_server}: {smtp_details}"
            
            if not result['smtp_valid']:
                result['error_message'] = f"SMTP验证失败: {result['smtp_details']}"
            
        except Exception as e:
            result['error_message'] = f'验证错误: {str(e)}'
        finally:
            result['time_taken'] = round((time.time() - start_time) * 1000)
        
        return result

def format_log_message(result):
    """格式化日志消息"""
    # 基本信息行
    base_info = "{:<30} {:<10} {:<6} {:<6} {:<6}".format(
        result['email'][:30],
        '✓ 有效' if result['is_valid'] else '✗ 无效',
        '✓' if result['has_mx'] else '✗',
        '✓' if result['smtp_valid'] else '✗',
        str(result['time_taken'])
    )
    
    # 详细信息
    details = [
        f"验证类型: {result['validation_type']}",
        f"MX服务器: {', '.join(result['mx_records'][:3]) if result['mx_records'] else 'N/A'}",
        f"SMTP详情: {result['smtp_details']}" if result['smtp_details'] else "",
        f"错误信息: {result['error_message']}" if result['error_message'] else ""
    ]
    
    # 过滤掉空字符串
    details = [d for d in details if d]
    
    # 组合消息
    if any(details):
        return f"{base_info}\n    " + "\n    ".join(details) + "\n"
    return base_info

def process_file(input_file: str, max_workers: int = 10):
    """处理CSV文件"""
    start_time = time.time()
    logging.info(f"开始处理文件: {input_file}")
    
    try:
        # 读取CSV文件
        df = pd.read_csv(input_file)
        total_emails = len(df)
        processed = 0
        valid_count = 0
        known_domain_count = 0
        
        logging.info(f"总共需要处理 {total_emails} 个邮箱\n")
        
        # 创建或更新结果列
        columns = ['valid_format', 'has_mx', 'smtp_valid', 'mx_servers', 
                  'error_message', 'smtp_details', 'validation_time_ms', 
                  'validation_type']
        for col in columns:
            if col not in df.columns:
                df[col] = ''
        
        # 打印表头
        logging.info("{:<30} {:<10} {:<6} {:<6} {:<6}".format(
            '邮箱', '结果', 'MX', 'SMTP', '耗时'
        ))
        logging.info("-" * 60)
        
        # 初始化验证器
        validator = EmailValidator()
        
        # 处理每个邮箱
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = {executor.submit(validator.validate_email, email): idx 
                      for idx, email in enumerate(df['email'])}
            
            for future in concurrent.futures.as_completed(futures):
                idx = futures[future]
                try:
                    result = future.result()
                    
                    # 更新DataFrame
                    for col in columns:
                        if col in result:
                            df.at[idx, col] = result[col]
                    
                    processed += 1
                    if result['is_valid']:
                        valid_count += 1
                    if result['validation_type'] == '已知域名':
                        known_domain_count += 1
                    
                    # 显示验证结果
                    logging.info(format_log_message(result))
                    
                    # 每处理100个邮箱保存一次并显示进度
                    if processed % 100 == 0:
                        df.to_csv(input_file, index=False)
                        progress = f"\n处理进度: {processed}/{total_emails} ({processed/total_emails*100:.1f}%)"
                        logging.info(f"{'-'*60}\n{progress}\n{'-'*60}\n")
                    
                except Exception as e:
                    logging.error(f"处理错误: {str(e)}")
        
        # 保存最终结果
        df.to_csv(input_file, index=False)
        
        # 打印统计信息
        total_time = time.time() - start_time
        logging.info(f"""
{'='*60}
验证完成:
- 总邮箱数: {total_emails}
- 有效邮箱数: {valid_count}
- 无效邮箱数: {total_emails - valid_count}
- 已知域名数: {known_domain_count}
- 需完整验证: {total_emails - known_domain_count}
- 有效率: {(valid_count/total_emails*100):.1f}%
- 总耗时: {total_time:.1f}秒
- 平均速度: {(total_time/total_emails*1000):.1f}毫秒/封
- 结果已保存到: {input_file}
{'='*60}
        """)
        
    except Exception as e:
        logging.error(f"处理过程发生错误: {str(e)}")
        raise

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("使用方法: python validator.py input.csv")
        sys.exit(1)
    
    input_file = sys.argv[1]
    process_file(input_file)
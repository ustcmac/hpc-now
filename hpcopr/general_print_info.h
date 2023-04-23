/*
 * This code is written and maintained by Zhenrong WANG (mailto: wangzhenrong@hpc-now.com) 
 * The founder of Shanghai HPC-NOW Technologies Co., Ltd (website: https://www.hpc-now.com)
 * It is distributed under the license: GNU Public License - v2.0
 * Bug report: info@hpc-now.com
 */

#ifndef GENERAL_PRINT_INFO_H
#define GENERAL_PRINT_INFO_H

void print_empty_cluster_info(void);
void print_cluster_init_done(void);
void print_help(void);
void print_header(void);
void print_tail(void);
void print_about(void);
int read_license(void);
int confirm_to_operate_cluster(char* current_cluster_name);

#endif
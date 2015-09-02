/*
 * interface.cpp
 *
 *  Created on: Jul 8, 2015
 *      Author: luanwenhao
 */

#include "interface.h"

#include <stdio.h>
#include <stdlib.h>
#include <string>
#include <iostream>
#include <fstream>
#include <sys/time.h>
#include <ctime>
#include <map>
#include <vector>
#include <algorithm>
#include <thrust/system_error.h>
#include <thrust/copy.h>
#include <thrust/device_vector.h>
#include <thrust/host_vector.h>

using namespace GaLG;
using namespace std;

namespace GaLG
{
	void
	load_table(inv_table& table, std::vector<std::vector<int> >& data_points)
	{
		  inv_list list;
		  u32 i,j;


		  printf("Data row size: %d. Data Row Number: %d.\n", data_points[0].size(), data_points.size());
		  for(i = 0; i < data_points[0].size(); ++i)
		  {
			  std::vector<int> col;
			  col.reserve(data_points.size());
			  for(j = 0; j < data_points.size(); ++j)
			  {
				  col.push_back(data_points[j][i]);
			  }
			  list.invert(col);
			  table.append(list);
		  }

		  table.build();
		  printf("Before finishing loading. i_size():%d, m_size():%d.\n", table.i_size(), table.m_size());
	}

	void
	load_query(inv_table& table,
				std::vector<query>& queries,
				GaLG_Config& config)
	{
		printf("Table dim: %d.\n", table.m_size());
		u32 i,j;
		int value;
		int radius = config.query_radius;
		std::vector<std::vector<int> >& query_points = *config.query_points;
		for(i = 0; i < query_points.size(); ++i)
		{
			query q(table, i);

			for(j = 0; j < query_points[i].size(); ++j){

				value = query_points[i][j];
				if(value < 0)
				{
					continue;
				}
				q.attr(j,
					   value - radius < 0 ? 0 : value - radius,
					   value + radius,
					   GALG_DEFAULT_WEIGHT);
			}

			q.topk(config.num_of_topk);
			q.selectivity(config.selectivity);
			if(config.use_adaptive_range)
			{
				q.apply_adaptive_query_range();
			}

			queries.push_back(q);
		}
		printf("%d queries are created!\n", queries.size());
	}
	void
	load_query_tweets(inv_table& table,
				std::vector<query>& queries,
				GaLG_Config& config)
	{

		printf("Table dim: %d.\n", table.m_size());
		u32 i,j;
		int value;
		int radius = config.query_radius;
		std::vector<std::vector<int> >& query_points = *config.query_points;
		for(i = 0; i < query_points.size(); ++i)
		{
			query q(table, i);

			for(j = 0; j < query_points[i].size(); ++j){

				value = query_points[i][j];
				if(value < 0)
				{
					continue;
				}
				q.attr(0,
					   value - radius < 0 ? 0 : value - radius,
					   value + radius,
					   GALG_DEFAULT_WEIGHT);
			}

			q.topk(config.num_of_topk);
			q.selectivity(config.selectivity);
			if(config.use_adaptive_range)
			{
				q.apply_adaptive_query_range();
			}

			queries.push_back(q);
		}
		printf("%d queries are created!\n", queries.size());
	}
	void
	load_table_tweets(inv_table& table, std::vector<std::vector<int> >& data_points)
	{
	  inv_list list;
	  list.invert_tweets(data_points);
	  table.append(list);
	  table.build();
	  printf("Before finishing loading. i_size():%d, m_size():%d.\n", table.i_size(), table.m_size());
	}
}
void GaLG::knn_search(std::vector<std::vector<int> >& data_points,
					  std::vector<std::vector<int> >& query_points,
					  std::vector<int>& result,
					  int num_of_topk)
{
	knn_search(data_points,
			   query_points,
			   result,
			   num_of_topk,
			   GALG_DEFAULT_RADIUS,
			   GALG_DEFAULT_THRESHOLD,
			   GALG_DEFAULT_HASHTABLE_SIZE,
			   GALG_DEFAULT_DEVICE);
}
void GaLG::knn_search(std::vector<std::vector<int> >& data_points,
					  std::vector<std::vector<int> >& query_points,
					  std::vector<int>& result,
					  int num_of_topk,
					  int radius,
					  int threshold,
					  float hashtable,
					  int device)
{
	GaLG_Config config;
	config.count_threshold = threshold;
	config.data_points = &data_points;
	config.hashtable_size = hashtable;
	config.num_of_topk = num_of_topk;
	config.query_points = &query_points;
	config.query_radius = radius;
	config.use_device = device;
	if(!query_points.empty())
		config.dim = query_points[0].size();

	knn_search(result, config);
}

void GaLG::knn_search_tweets(std::vector<int>& result, GaLG_Config& config)
{
	inv_table table;
	std::vector<query> queries;
	printf("Building table...");
	load_table_tweets(table, *(config.data_points));
	printf("Done!\n");
	printf("Loading queries...");
	load_query_tweets(table,queries,config);
	printf("Done!\n");
	knn_search(table, queries, result, config);
}

void GaLG::knn_search(std::vector<int>& result, GaLG_Config& config)
{
	inv_table table;
	std::vector<query> queries;
	printf("Building table...");
	load_table(table, *(config.data_points));
	printf("Done!\n");
	printf("Loading queries...");
	load_query(table,queries,config);
	printf("Done!\n");
	knn_search(table, queries, result, config);
}


void GaLG::knn_search(inv_table& table,
					  std::vector<query>& queries,
					  std::vector<int>& h_topk,
					  GaLG_Config& config)
{
	int device_count, hashtable_size;
	cudaGetDeviceCount(&device_count);
	if(device_count == 0)
	{
		printf("[Info] NVIDIA CUDA-SUPPORTED GPU NOT FOUND!\nProgram aborted..\n");
		exit(2);
	} else if(device_count <= config.use_device)
	{
		printf("[Info] Device %d not found!", config.use_device);
		config.use_device = GALG_DEFAULT_DEVICE;
	}
	cudaSetDevice(config.use_device);
	cudaDeviceReset();
	cudaDeviceSynchronize();
	printf("Using device %d...\n", config.use_device);
	printf("table.i_size():%d, config.hashtable_size:%f.\n", table.i_size(), config.hashtable_size);
	hashtable_size = table.i_size() * config.hashtable_size + 1;
	thrust::device_vector<int> d_topk;

	printf("Starting knn search...\n");
	//printf("KNN Pre-condition Check: print query 0\n");
	//queries[0].print();
	GaLG::topk_tweets(table,
			   queries,
			   d_topk,
			   hashtable_size,
			   config.count_threshold,
			   config.dim,
			   config.num_of_hot_dims,
			   config.hot_dim_threshold);
	printf("knn search is done!\n");

	printf("Topk obtained: %d in total.\n", d_topk.size());
	h_topk.resize(d_topk.size());

	thrust::copy(d_topk.begin(), d_topk.end(), h_topk.begin());
}




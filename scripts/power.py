#!/usr/bin/env python3
import zipfile
import json
import re
from datetime import datetime
import argparse
import statistics
import logging, logging.config
import sys

def calculate_power_hour_ratio(start, end):
    time_format = "%d.%m.%y, %H:%M"
    start_time = datetime.strptime(start['time'], time_format)
    end_time = datetime.strptime(end['time'], time_format)
    time_diff_hours = (end_time - start_time).total_seconds() / 3600
    logger.debug(f"{time_diff_hours=}, {start_time=}, {end_time=}, {start['power']=}, {end['power']=}, {start['charging']=}, {end['charging']=}")
    if time_diff_hours == 0:
        return None
    return (end['power'] - start['power']) / time_diff_hours

def process_zip(zip_file_path):
    logger.info(f"Processing zip file at '{zip_file_path}'...")
    data_points = []
    with zipfile.ZipFile(zip_file_path, 'r') as zip_file:
        sorted_files = []
        for file_name in zip_file.namelist():
            if re.match(r'^[^/]+-(\d+)\.json$', file_name):
                sorted_files.append((re.search(r'^[^/]+-(\d+)\.json$', file_name).group(1), file_name))
            elif re.match(r'^[^/]+\.json$', file_name):
                sorted_files.append(("1", file_name))
        sorted_files.sort(key=lambda x: int(x[0]))
        print(sorted_files)
        for _, file_name in sorted_files:
            logger.debug(f"Parsing file: {file_name}")
            with zip_file.open(file_name) as json_file:
                data = json.load(json_file)
                data_points.append(data)
    logger.info(f"Zip file successfully processed, {len(data_points)} data-points extracted...")
    return data_points

def calculate_power_ratios(data_points):
    logger.info(f"Calculating power ratios...")
    discharging = []
    charging = []
    ignored_discharging_periods = 0
    ignored_charging_periods = 0
    for i in range(1, len(data_points)):
        start = data_points[i-1]
        end = data_points[i]
        power_hour_ratio = calculate_power_hour_ratio(start, end)
        if start['charging'] == False and end['charging'] == True:
            if power_hour_ratio is None or power_hour_ratio > 0:
                ignored_discharging_periods += 1
                logger.debug(f"Ignoring discharging period: {start} - {end} --> {power_hour_ratio}...")
                continue
            discharging.append(power_hour_ratio)
        elif start['charging'] == True and end['charging'] == False:
            if power_hour_ratio is None or power_hour_ratio < 0:
                ignored_charging_periods += 1
                logger.debug(f"Ignoring charging period: {start} - {end}...")
                continue
            charging.append(power_hour_ratio)
        elif start['charging'] == True and end['charging'] == True:
            if power_hour_ratio is None or power_hour_ratio < 0:
                ignored_charging_periods += 1
                logger.debug(f"Ignoring charging period: {start} - {end} --> {power_hour_ratio}...")
                continue
            charging.append(power_hour_ratio)
        else:
            logger.error(f"Unexpected ({'unusable' if power_hour_ratio is None else 'usable'}) datapoints: {start}, {end}")
            continue
    discharging_median = statistics.median(discharging) if len(discharging)>0 else 0
    discharging_mean = statistics.mean(discharging) if len(discharging)>0 else 0
    charging_median = statistics.median(charging) if len(charging)>0 else 0
    charging_mean = statistics.mean(charging) if len(charging)>0 else 0
    logger.info(f"Power ratios calculated: {len(discharging)+ignored_discharging_periods} discharging periods ({len(discharging)} usable), {len(charging)+ignored_charging_periods} charging periods ({len(charging)} usable)...")
    return discharging, discharging_median, discharging_mean, charging, charging_median, charging_mean

parser = argparse.ArgumentParser(description="Process a zip file of JSON files containing power, time, and charging data.")
parser.add_argument('--file', metavar='file.zip', required=True, help="Path to the zip file")
parser.add_argument("--log", metavar='LOGLEVEL', help="Loglevel to log", default="INFO")
args = parser.parse_args()

logging.config.dictConfig({
	"version": 1,
	"disable_existing_loggers": False,
	
	"formatters": {
		"simple": {
			"format": "%(asctime)s [%(levelname)-7s] %(name)s {%(threadName)s} %(filename)s:%(lineno)d: %(message)s",
			"color": True
		}
	},
	
	"handlers": {
		"stderr": {
			"class": "logging.StreamHandler",
			"level": args.log,
			"formatter": "simple"
		},
		"ignore": {
			"class": "logging.NullHandler",
			"level": "DEBUG"
		}
	},
	
	"loggers": {
		"": {
			"level": "DEBUG",
			"handlers": ["stderr"]
		}
	}
})
logger = logging.getLogger(__name__)

data_points = process_zip(args.file)
discharging, discharging_median, discharging_mean, charging, charging_median, charging_mean = calculate_power_ratios(data_points)

print(f"Discharging ratios (median: {discharging_median:.3f}, mean: {discharging_mean:.3f}):", discharging)
print(f"Charging ratios (median: {charging_median:.3f}, mean: {charging_mean:.3f}):", charging)

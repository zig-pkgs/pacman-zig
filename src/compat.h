#include "conf.h"

struct pacman_progress_bar {
	config_t *config;
	char *filename;
	off_t xfered; /* Current amount of transferred data */
	off_t total_size;
	size_t downloaded;
	size_t howmany;
	uint64_t init_time; /* Time when this download started doing any progress */
	uint64_t sync_time; /* Last time we updated the bar info */
	off_t sync_xfered; /* Amount of transferred data at the `sync_time` timestamp. It can be
	                      smaller than `xfered` if we did not update bar UI for a while. */
	double rate;
	unsigned int eta; /* ETA in seconds */
	bool completed; /* transfer is completed */
};

/* This datastruct represents the state of multiline progressbar UI */
struct pacman_multibar_ui {
	/* List of active downloads handled by multibar UI.
	 * Once the first download in the list is completed it is removed
	 * from this list and we never redraw it anymore.
	 * If the download is in this list, then the UI can redraw the progress bar or change
	 * the order of the bars (e.g. moving completed bars to the top of the list)
	 */
	alpm_list_t *active_downloads; /* List of type 'struct pacman_progress_bar' */

	/* Number of active download bars that multibar UI handles. */
	size_t active_downloads_num;

	/* Specifies whether a completed progress bar need to be reordered and moved
	 * to the top of the list.
	 */
	bool move_completed_up;

	/* Cursor position relative to the first active progress bar,
	 * e.g. 0 means the first active progress bar, active_downloads_num-1 means the last bar,
	 * active_downloads_num - is the line below all progress bars.
	 */
	int cursor_lineno;
};

extern int on_progress;
extern alpm_list_t *output;

int dload_progressbar_enabled(config_t *config);
void init_total_progressbar(config_t *config);
void update_bar_finalstats(struct pacman_progress_bar *bar);
void draw_pacman_progress_bar(struct pacman_progress_bar *bar);

void dload_init_event(config_t *_config, const char *filename, alpm_download_event_init_t *data);
void dload_progress_event(config_t *_config, const char *filename, alpm_download_event_progress_t *data);
void dload_retry_event(config_t *_config, const char *filename, alpm_download_event_retry_t *data);
void dload_complete_event(config_t *_config, const char *filename, alpm_download_event_completed_t *data);

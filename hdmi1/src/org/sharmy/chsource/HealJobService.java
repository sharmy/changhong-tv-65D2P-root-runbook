package org.sharmy.chsource;

import android.app.job.JobParameters;
import android.app.job.JobService;
import android.os.AsyncTask;
import android.util.Log;

/**
 * JobScheduler 触发的自愈执行体。
 * 用 JobScheduler 是因为长虹会拦第三方 app 的 BOOT_COMPLETED，
 * 而 JobScheduler 的任务由系统持久化并调度，开机后系统自己拉起。
 */
public class HealJobService extends JobService {

    private static final String TAG = "ChSourceHeal";

    @Override
    public boolean onStartJob(final JobParameters params) {
        Log.i(TAG, "JobScheduler 触发自愈");
        new AsyncTask<Void, Void, Void>() {
            @Override
            protected Void doInBackground(Void... v) {
                Healer.run(getApplicationContext(), "job");
                return null;
            }

            @Override
            protected void onPostExecute(Void v) {
                try {
                    jobFinished(params, false);
                } catch (Throwable t) {
                    Log.w(TAG, "jobFinished 失败", t);
                }
            }
        }.execute();
        return true;   // 有异步工作
    }

    @Override
    public boolean onStopJob(JobParameters params) {
        return false;
    }
}

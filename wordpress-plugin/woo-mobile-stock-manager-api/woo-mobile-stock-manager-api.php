<?php
/**
 * Plugin Name: Modiriat Sari API
 * Description: REST API امن برای اپلیکیشن مدیریت محصولات ووکامرس + ارسال به بله + تغییر تصویر شاخص + مرتب‌سازی، گرادیانت اکشن‌ها و موجودی بدون محدودیت.
 * Version: 1.7.0
 * Author: شهرام سعیدنیا
 * Text Domain: woo-mobile-stock-manager-api
 */

if (!defined('ABSPATH')) {
    exit;
}

final class WMSM_Woo_Mobile_Stock_Manager_API {
    private const NAMESPACE = 'wmsm/v1';
    private const TOKEN_HASH_META = '_wmsm_api_token_hash';
    private const TOKEN_EXPIRES_META = '_wmsm_api_token_expires';
    private const TOKEN_DAYS = 30;

    private const BALE_BOT_TOKEN_OPTION = 'wmsm_bale_bot_token';
    private const BALE_CHAT_ID_OPTION = 'wmsm_bale_chat_id';
    private const BALE_JOBS_OPTION = 'wmsm_bale_auto_jobs';
    private const BALE_CRON_HOOK = 'wmsm_bale_auto_send_product';
    private const BALE_COOLDOWN_SECONDS = 3600;
    private const LAST_ACTION_META = '_wmsm_last_action';
    private const LAST_ACTION_AT_META = '_wmsm_last_action_at';
    private const UPDATED_ACTION_AT_META = '_wmsm_updated_action_at';
    private const BALE_SENT_ACTION_AT_META = '_wmsm_bale_sent_action_at';

    private $authorized_user = null;

    public function __construct() {
        add_action('rest_api_init', [$this, 'register_routes']);
        add_action('admin_notices', [$this, 'woocommerce_admin_notice']);
        add_action(self::BALE_CRON_HOOK, [$this, 'run_bale_auto_job'], 10, 1);
    }

    public function woocommerce_admin_notice(): void {
        if (!current_user_can('activate_plugins')) {
            return;
        }

        if (!class_exists('WooCommerce')) {
            echo '<div class="notice notice-warning"><p>' . esc_html__('افزونه Woo Mobile Stock Manager API فعال است، اما WooCommerce نصب یا فعال نیست.', 'woo-mobile-stock-manager-api') . '</p></div>';
        }
    }

    public function register_routes(): void {
        register_rest_route(self::NAMESPACE, '/login', [
            'methods' => WP_REST_Server::CREATABLE,
            'callback' => [$this, 'login'],
            'permission_callback' => '__return_true',
            'args' => [
                'username' => ['required' => true, 'type' => 'string'],
                'password' => ['required' => true, 'type' => 'string'],
            ],
        ]);

        register_rest_route(self::NAMESPACE, '/categories', [
            'methods' => WP_REST_Server::READABLE,
            'callback' => [$this, 'get_categories'],
            'permission_callback' => [$this, 'can_access'],
        ]);

        register_rest_route(self::NAMESPACE, '/products', [
            'methods' => WP_REST_Server::READABLE,
            'callback' => [$this, 'get_products'],
            'permission_callback' => [$this, 'can_access'],
            'args' => [
                'category_id' => ['required' => false, 'type' => 'integer', 'sanitize_callback' => 'absint'],
                'search' => ['required' => false, 'type' => 'string', 'sanitize_callback' => 'sanitize_text_field'],
                'sort' => ['required' => false, 'type' => 'string', 'default' => 'newest', 'sanitize_callback' => 'sanitize_text_field'],
                'page' => ['required' => false, 'type' => 'integer', 'default' => 1, 'sanitize_callback' => 'absint'],
                'per_page' => ['required' => false, 'type' => 'integer', 'default' => 20, 'sanitize_callback' => 'absint'],
            ],
        ]);

        register_rest_route(self::NAMESPACE, '/products/(?P<id>\d+)', [
            [
                'methods' => WP_REST_Server::READABLE,
                'callback' => [$this, 'get_product'],
                'permission_callback' => [$this, 'can_access'],
                'args' => ['id' => ['required' => true, 'type' => 'integer', 'sanitize_callback' => 'absint']],
            ],
            [
                'methods' => WP_REST_Server::EDITABLE,
                'callback' => [$this, 'update_product'],
                'permission_callback' => [$this, 'can_access'],
                'args' => ['id' => ['required' => true, 'type' => 'integer', 'sanitize_callback' => 'absint']],
            ],
        ]);


        register_rest_route(self::NAMESPACE, '/products/(?P<id>\d+)/featured-image', [
            'methods' => WP_REST_Server::CREATABLE,
            'callback' => [$this, 'update_product_featured_image'],
            'permission_callback' => [$this, 'can_access'],
            'args' => [
                'id' => ['required' => true, 'type' => 'integer', 'sanitize_callback' => 'absint'],
            ],
        ]);

        register_rest_route(self::NAMESPACE, '/products/(?P<id>\d+)/bale-send', [
            'methods' => WP_REST_Server::CREATABLE,
            'callback' => [$this, 'send_product_to_bale'],
            'permission_callback' => [$this, 'can_access'],
            'args' => [
                'id' => ['required' => true, 'type' => 'integer', 'sanitize_callback' => 'absint'],
                'manual_text' => ['required' => false, 'type' => 'string', 'sanitize_callback' => 'sanitize_textarea_field'],
            ],
        ]);

        register_rest_route(self::NAMESPACE, '/bale/settings', [
            [
                'methods' => WP_REST_Server::READABLE,
                'callback' => [$this, 'get_bale_settings'],
                'permission_callback' => [$this, 'can_access'],
            ],
            [
                'methods' => WP_REST_Server::CREATABLE,
                'callback' => [$this, 'save_bale_settings'],
                'permission_callback' => [$this, 'can_access'],
                'args' => [
                    'bot_token' => ['required' => false, 'type' => 'string'],
                    'chat_id' => ['required' => true, 'type' => 'string'],
                ],
            ],
        ]);

        register_rest_route(self::NAMESPACE, '/bale/auto-start', [
            'methods' => WP_REST_Server::CREATABLE,
            'callback' => [$this, 'start_bale_auto_job'],
            'permission_callback' => [$this, 'can_access'],
            'args' => [
                'category_id' => ['required' => true, 'type' => 'integer', 'sanitize_callback' => 'absint'],
                'interval_minutes' => ['required' => true, 'type' => 'integer', 'sanitize_callback' => 'absint'],
                'manual_text' => ['required' => false, 'type' => 'string', 'sanitize_callback' => 'sanitize_textarea_field'],
            ],
        ]);

        register_rest_route(self::NAMESPACE, '/bale/auto-stop', [
            'methods' => WP_REST_Server::CREATABLE,
            'callback' => [$this, 'stop_bale_auto_job'],
            'permission_callback' => [$this, 'can_access'],
            'args' => [
                'category_id' => ['required' => true, 'type' => 'integer', 'sanitize_callback' => 'absint'],
            ],
        ]);

        register_rest_route(self::NAMESPACE, '/bale/auto-jobs', [
            'methods' => WP_REST_Server::READABLE,
            'callback' => [$this, 'get_bale_auto_jobs'],
            'permission_callback' => [$this, 'can_access'],
        ]);
    }

    public function login(WP_REST_Request $request) {
        $wc_error = $this->ensure_woocommerce();
        if (is_wp_error($wc_error)) {
            return $wc_error;
        }

        $username = sanitize_user((string) $request->get_param('username'));
        $password = (string) $request->get_param('password');

        if ($username === '' || $password === '') {
            return $this->error('wmsm_missing_login_fields', 'نام کاربری و رمز عبور را وارد کنید.', 400);
        }

        $user = wp_authenticate($username, $password);
        if (is_wp_error($user)) {
            return $this->error('wmsm_invalid_login', 'نام کاربری یا رمز عبور اشتباه است.', 401);
        }

        if (!$this->user_can_manage_products($user)) {
            return $this->error('wmsm_forbidden_user', 'این کاربر اجازه مدیریت محصولات را ندارد.', 403);
        }

        $secret = $this->create_random_secret();
        $hash = wp_hash_password($secret);
        $expires = time() + (DAY_IN_SECONDS * self::TOKEN_DAYS);

        update_user_meta($user->ID, self::TOKEN_HASH_META, $hash);
        update_user_meta($user->ID, self::TOKEN_EXPIRES_META, $expires);

        return rest_ensure_response([
            'token' => $user->ID . ':' . $secret,
            'expires_at' => gmdate('c', $expires),
            'user' => [
                'id' => (int) $user->ID,
                'display_name' => $user->display_name,
            ],
        ]);
    }

    public function get_categories(WP_REST_Request $request) {
        $wc_error = $this->ensure_woocommerce();
        if (is_wp_error($wc_error)) {
            return $wc_error;
        }

        $terms = get_terms([
            'taxonomy' => 'product_cat',
            'hide_empty' => true,
            'orderby' => 'name',
            'order' => 'ASC',
        ]);

        if (is_wp_error($terms)) {
            return $this->error('wmsm_categories_failed', 'دسته‌بندی‌ها دریافت نشدند.', 500);
        }

        $items = [];
        foreach ($terms as $term) {
            $items[] = [
                'id' => (int) $term->term_id,
                'name' => html_entity_decode($term->name, ENT_QUOTES, get_bloginfo('charset')),
                'count' => (int) $term->count,
            ];
        }

        return rest_ensure_response($items);
    }

    public function get_products(WP_REST_Request $request) {
        $wc_error = $this->ensure_woocommerce();
        if (is_wp_error($wc_error)) {
            return $wc_error;
        }

        $page = max(1, absint($request->get_param('page')));
        $per_page = absint($request->get_param('per_page'));
        $per_page = min(50, max(1, $per_page ?: 20));
        $category_id = absint($request->get_param('category_id'));
        $search = sanitize_text_field((string) $request->get_param('search'));
        $sort = sanitize_text_field((string) $request->get_param('sort'));
        if (!in_array($sort, ['newest', 'oldest', 'price_desc', 'price_asc'], true)) {
            $sort = 'newest';
        }

        $args = [
            'post_type' => 'product',
            'post_status' => ['publish', 'private', 'draft', 'pending'],
            'posts_per_page' => $per_page,
            'paged' => $page,
            'orderby' => 'date',
            'order' => 'DESC',
            'fields' => 'ids',
        ];

        if ($sort === 'oldest') {
            $args['orderby'] = 'date';
            $args['order'] = 'ASC';
        } elseif ($sort === 'price_desc') {
            $args['meta_key'] = '_price';
            $args['orderby'] = 'meta_value_num';
            $args['order'] = 'DESC';
        } elseif ($sort === 'price_asc') {
            $args['meta_key'] = '_price';
            $args['orderby'] = 'meta_value_num';
            $args['order'] = 'ASC';
        }

        if ($search !== '') {
            $args['s'] = $search;
        }

        if ($category_id > 0) {
            $args['tax_query'] = [[
                'taxonomy' => 'product_cat',
                'field' => 'term_id',
                'terms' => [$category_id],
            ]];
        }

        $query = new WP_Query($args);
        $items = [];
        foreach ($query->posts as $product_id) {
            $product = wc_get_product($product_id);
            if ($product instanceof WC_Product) {
                $items[] = $this->format_product($product);
            }
        }

        return rest_ensure_response([
            'items' => $items,
            'page' => $page,
            'per_page' => $per_page,
            'total' => (int) $query->found_posts,
            'total_pages' => (int) $query->max_num_pages,
        ]);
    }

    public function get_product(WP_REST_Request $request) {
        $wc_error = $this->ensure_woocommerce();
        if (is_wp_error($wc_error)) {
            return $wc_error;
        }

        $product_id = absint($request['id']);
        $product = wc_get_product($product_id);

        if (!$product) {
            return $this->error('wmsm_product_not_found', 'محصول پیدا نشد.', 404);
        }

        if (!$this->can_edit_this_product($product_id)) {
            return $this->error('wmsm_product_forbidden', 'اجازه ویرایش این محصول را ندارید.', 403);
        }

        return rest_ensure_response($this->format_product($product));
    }

    public function update_product(WP_REST_Request $request) {
        $wc_error = $this->ensure_woocommerce();
        if (is_wp_error($wc_error)) {
            return $wc_error;
        }

        $product_id = absint($request['id']);
        $product = wc_get_product($product_id);

        if (!$product) {
            return $this->error('wmsm_product_not_found', 'محصول پیدا نشد.', 404);
        }

        if (!$this->can_edit_this_product($product_id)) {
            return $this->error('wmsm_product_forbidden', 'اجازه ویرایش این محصول را ندارید.', 403);
        }

        $regular_price = $request->get_param('regular_price');
        $stock_quantity = $request->get_param('stock_quantity');
        $stock_status = $request->get_param('stock_status');

        if ($regular_price === null && $stock_quantity === null && $stock_status === null) {
            return $this->error('wmsm_no_update_fields', 'هیچ اطلاعاتی برای ذخیره ارسال نشده است.', 400);
        }

        if ($regular_price !== null) {
            $regular_price = wc_format_decimal(wp_unslash((string) $regular_price));
            if ($regular_price === '' || !is_numeric($regular_price) || (float) $regular_price < 0) {
                return $this->error('wmsm_invalid_price', 'قیمت محصول معتبر نیست.', 400);
            }
            $product->set_regular_price($regular_price);
        }

        if ($stock_quantity !== null) {
            $stock_quantity_raw = trim((string) wp_unslash($stock_quantity));

            // خالی یا ۰ یعنی محدودیت تعداد نداریم و مدیریت موجودی عددی غیرفعال می‌شود.
            if ($stock_quantity_raw === '' || $stock_quantity_raw === '0') {
                $product->set_manage_stock(false);
                $product->set_stock_quantity(null);
            } else {
                if (!is_numeric($stock_quantity_raw) || (int) $stock_quantity_raw < 0) {
                    return $this->error('wmsm_invalid_stock_quantity', 'تعداد موجودی معتبر نیست.', 400);
                }
                $product->set_manage_stock(true);
                $product->set_stock_quantity(wc_stock_amount($stock_quantity_raw));
            }
        }

        if ($stock_status !== null) {
            $stock_status = sanitize_text_field((string) $stock_status);
            if (!in_array($stock_status, ['instock', 'outofstock'], true)) {
                return $this->error('wmsm_invalid_stock_status', 'وضعیت موجودی فقط می‌تواند instock یا outofstock باشد.', 400);
            }
            $product->set_stock_status($stock_status);
        }

        try {
            $product->save();
            $this->set_product_last_action($product_id, 'updated');
        } catch (Exception $e) {
            return $this->error('wmsm_save_failed', 'ذخیره محصول انجام نشد.', 500);
        }

        return rest_ensure_response($this->format_product($product));
    }


    public function update_product_featured_image(WP_REST_Request $request) {
        $wc_error = $this->ensure_woocommerce();
        if (is_wp_error($wc_error)) {
            return $wc_error;
        }

        $product_id = absint($request['id']);
        $product = wc_get_product($product_id);

        if (!$product) {
            return $this->error('wmsm_product_not_found', 'محصول پیدا نشد.', 404);
        }

        if (!$this->can_edit_this_product($product_id)) {
            return $this->error('wmsm_product_forbidden', 'اجازه ویرایش این محصول را ندارید.', 403);
        }

        $files = $request->get_file_params();
        if (empty($files['image']) || !is_array($files['image'])) {
            return $this->error('wmsm_image_missing', 'فایل تصویر ارسال نشده است.', 400);
        }

        $file = $files['image'];
        if (!empty($file['error'])) {
            return $this->error('wmsm_image_upload_error', 'آپلود تصویر انجام نشد. لطفاً دوباره تلاش کنید.', 400);
        }

        $max_size = 10 * 1024 * 1024;
        if (!empty($file['size']) && (int) $file['size'] > $max_size) {
            return $this->error('wmsm_image_too_large', 'حجم تصویر نباید بیشتر از ۱۰ مگابایت باشد.', 400);
        }

        $allowed_mimes = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
        $mime_type = !empty($file['type']) ? sanitize_mime_type($file['type']) : '';
        if ($mime_type !== '' && !in_array($mime_type, $allowed_mimes, true)) {
            return $this->error('wmsm_image_invalid_type', 'فرمت تصویر باید JPG، PNG، WEBP یا GIF باشد.', 400);
        }

        require_once ABSPATH . 'wp-admin/includes/file.php';
        require_once ABSPATH . 'wp-admin/includes/media.php';
        require_once ABSPATH . 'wp-admin/includes/image.php';

        $attachment_id = media_handle_sideload($file, $product_id, $product->get_name());
        if (is_wp_error($attachment_id)) {
            return $this->error('wmsm_image_save_failed', 'ذخیره تصویر در وردپرس انجام نشد: ' . $attachment_id->get_error_message(), 500);
        }

        update_post_meta($attachment_id, '_wp_attachment_image_alt', $product->get_name());

        try {
            $product->set_image_id((int) $attachment_id);
            $product->save();
            $this->set_product_last_action($product_id, 'updated');
        } catch (Exception $e) {
            return $this->error('wmsm_image_product_save_failed', 'تصویر آپلود شد اما روی محصول ذخیره نشد.', 500);
        }

        return rest_ensure_response($this->format_product($product));
    }

    public function get_bale_settings(WP_REST_Request $request) {
        return rest_ensure_response([
            'has_bot_token' => $this->get_bale_bot_token() !== '',
            'chat_id' => $this->get_bale_chat_id(),
            'jobs' => $this->format_bale_jobs(),
        ]);
    }

    public function save_bale_settings(WP_REST_Request $request) {
        $chat_id = trim(sanitize_text_field((string) $request->get_param('chat_id')));
        $bot_token = trim(sanitize_text_field((string) $request->get_param('bot_token')));

        if ($chat_id === '') {
            return $this->error('wmsm_bale_chat_id_missing', 'شناسه یا نام کاربری کانال بله را وارد کنید.', 400);
        }

        if ($bot_token !== '') {
            update_option(self::BALE_BOT_TOKEN_OPTION, $bot_token, false);
        }
        update_option(self::BALE_CHAT_ID_OPTION, $chat_id, false);

        return rest_ensure_response([
            'message' => 'تنظیمات بله ذخیره شد.',
            'has_bot_token' => $this->get_bale_bot_token() !== '',
            'chat_id' => $this->get_bale_chat_id(),
        ]);
    }

    public function send_product_to_bale(WP_REST_Request $request) {
        $wc_error = $this->ensure_woocommerce();
        if (is_wp_error($wc_error)) {
            return $wc_error;
        }

        $product_id = absint($request['id']);
        $product = wc_get_product($product_id);
        if (!$product) {
            return $this->error('wmsm_product_not_found', 'محصول پیدا نشد.', 404);
        }
        if (!$this->can_edit_this_product($product_id)) {
            return $this->error('wmsm_product_forbidden', 'اجازه ارسال این محصول را ندارید.', 403);
        }

        $remaining = $this->get_bale_cooldown_remaining($product_id);
        if ($remaining > 0) {
            return $this->error('wmsm_bale_cooldown', 'این محصول تازه ارسال شده است. تا ' . $this->format_seconds($remaining) . ' دیگر دوباره قابل ارسال است.', 429);
        }

        $manual_text = sanitize_textarea_field((string) $request->get_param('manual_text'));
        $result = $this->send_product_post_to_bale($product, $manual_text);
        if (is_wp_error($result)) {
            return $result;
        }

        $this->set_bale_cooldown($product_id);
        $this->set_product_last_action($product_id, 'bale_sent');

        // محصول بعد از ثبت اکشن برگردانده می‌شود تا اپ همان لحظه رنگ گرادیانت را درست نمایش بدهد.
        $fresh_product = wc_get_product($product_id);

        return rest_ensure_response([
            'message' => 'محصول در کانال بله منتشر شد.',
            'cooldown_remaining' => self::BALE_COOLDOWN_SECONDS,
            'product' => $fresh_product ? $this->format_product($fresh_product) : null,
        ]);
    }

    public function start_bale_auto_job(WP_REST_Request $request) {
        $wc_error = $this->ensure_woocommerce();
        if (is_wp_error($wc_error)) {
            return $wc_error;
        }

        $settings_error = $this->ensure_bale_settings();
        if (is_wp_error($settings_error)) {
            return $settings_error;
        }

        $category_id = absint($request->get_param('category_id'));
        $interval = absint($request->get_param('interval_minutes'));
        $manual_text = sanitize_textarea_field((string) $request->get_param('manual_text'));
        $allowed = [3, 60, 420, 1440];

        if ($category_id <= 0) {
            return $this->error('wmsm_bale_category_required', 'برای ارسال خودکار باید یک دسته‌بندی انتخاب شود.', 400);
        }
        if (!in_array($interval, $allowed, true)) {
            return $this->error('wmsm_bale_invalid_interval', 'بازه ارسال فقط می‌تواند ۳ دقیقه، ۱ ساعت، ۷ ساعت یا ۲۴ ساعت باشد.', 400);
        }

        $term = get_term($category_id, 'product_cat');
        if (!$term || is_wp_error($term)) {
            return $this->error('wmsm_bale_category_not_found', 'دسته‌بندی پیدا نشد.', 404);
        }

        $product_ids = $this->get_product_ids_by_category($category_id);
        if (empty($product_ids)) {
            return $this->error('wmsm_bale_empty_category', 'در این دسته‌بندی محصولی برای ارسال پیدا نشد.', 400);
        }

        $jobs = $this->get_bale_jobs();
        $jobs[(string) $category_id] = [
            'category_id' => $category_id,
            'category_name' => html_entity_decode($term->name, ENT_QUOTES, get_bloginfo('charset')),
            'interval_minutes' => $interval,
            'manual_text' => $manual_text,
            'product_ids' => array_values($product_ids),
            'index' => 0,
            'total' => count($product_ids),
            'started_at' => time(),
            'next_run' => time() + 60,
            'status' => 'active',
        ];
        update_option(self::BALE_JOBS_OPTION, $jobs, false);

        wp_clear_scheduled_hook(self::BALE_CRON_HOOK, [$category_id]);
        wp_schedule_single_event(time() + 60, self::BALE_CRON_HOOK, [$category_id]);

        return rest_ensure_response([
            'message' => 'ارسال خودکار این دسته‌بندی فعال شد. اولین محصول حدود یک دقیقه دیگر ارسال می‌شود.',
            'category_id' => $category_id,
            'total' => count($product_ids),
            'interval_minutes' => $interval,
            'next_run' => gmdate('c', time() + 60),
        ]);
    }

    public function stop_bale_auto_job(WP_REST_Request $request) {
        $category_id = absint($request->get_param('category_id'));
        $jobs = $this->get_bale_jobs();
        if (isset($jobs[(string) $category_id])) {
            unset($jobs[(string) $category_id]);
            update_option(self::BALE_JOBS_OPTION, $jobs, false);
        }
        wp_clear_scheduled_hook(self::BALE_CRON_HOOK, [$category_id]);

        return rest_ensure_response(['message' => 'ارسال خودکار این دسته‌بندی متوقف شد.']);
    }

    public function get_bale_auto_jobs(WP_REST_Request $request) {
        return rest_ensure_response(['jobs' => $this->format_bale_jobs()]);
    }

    public function run_bale_auto_job($category_id): void {
        $category_id = absint($category_id);
        if ($category_id <= 0 || !function_exists('wc_get_product')) {
            return;
        }

        $jobs = $this->get_bale_jobs();
        $key = (string) $category_id;
        if (empty($jobs[$key]) || ($jobs[$key]['status'] ?? '') !== 'active') {
            return;
        }

        $job = $jobs[$key];
        $product_ids = array_values(array_filter(array_map('absint', $job['product_ids'] ?? [])));
        $index = max(0, absint($job['index'] ?? 0));
        $interval = max(3, absint($job['interval_minutes'] ?? 60));

        if ($index >= count($product_ids)) {
            unset($jobs[$key]);
            update_option(self::BALE_JOBS_OPTION, $jobs, false);
            return;
        }

        $product = wc_get_product($product_ids[$index]);
        if ($product instanceof WC_Product) {
            $result = $this->send_product_post_to_bale($product, (string) ($job['manual_text'] ?? ''), true);
            if (!is_wp_error($result)) {
                $this->set_product_last_action($product->get_id(), 'bale_sent');
            }
        }

        $index++;
        if ($index >= count($product_ids)) {
            unset($jobs[$key]);
            update_option(self::BALE_JOBS_OPTION, $jobs, false);
            return;
        }

        $next_run = time() + ($interval * MINUTE_IN_SECONDS);
        $jobs[$key]['index'] = $index;
        $jobs[$key]['next_run'] = $next_run;
        update_option(self::BALE_JOBS_OPTION, $jobs, false);

        wp_schedule_single_event($next_run, self::BALE_CRON_HOOK, [$category_id]);
    }

    public function can_access(WP_REST_Request $request) {
        $wc_error = $this->ensure_woocommerce();
        if (is_wp_error($wc_error)) {
            return $wc_error;
        }

        $user = $this->authenticate_token($request);
        if (is_wp_error($user)) {
            return $user;
        }

        if (!$this->user_can_manage_products($user)) {
            return $this->error('wmsm_forbidden_user', 'این کاربر اجازه مدیریت محصولات را ندارد.', 403);
        }

        $this->authorized_user = $user;
        wp_set_current_user($user->ID);
        return true;
    }

    private function send_product_post_to_bale(WC_Product $product, string $manual_text = '', bool $ignore_cooldown = false) {
        $settings_error = $this->ensure_bale_settings();
        if (is_wp_error($settings_error)) {
            return $settings_error;
        }

        if (!$ignore_cooldown && $this->get_bale_cooldown_remaining($product->get_id()) > 0) {
            return $this->error('wmsm_bale_cooldown', 'این محصول تازه ارسال شده است.', 429);
        }

        $token = $this->get_bale_bot_token();
        $chat_id = $this->get_bale_chat_id();
        $caption = $this->build_bale_caption($product, $manual_text);
        $image_url = $this->get_product_image_url($product, 'full');
        $reply_markup = $this->build_bale_order_button($product);

        if ($image_url !== '') {
            $payload = [
                'chat_id' => $chat_id,
                'photo' => $image_url,
                'caption' => $this->limit_text($caption, 3900),
            ];

            if (!empty($reply_markup)) {
                $payload['reply_markup'] = $reply_markup;
            }

            return $this->call_bale_api('sendPhoto', $payload, $token);
        }

        $payload = [
            'chat_id' => $chat_id,
            'text' => $this->limit_text($caption, 3900),
        ];

        if (!empty($reply_markup)) {
            $payload['reply_markup'] = $reply_markup;
        }

        return $this->call_bale_api('sendMessage', $payload, $token);
    }

    private function call_bale_api(string $method, array $payload, string $token) {
        $safe_token = str_replace('%3A', ':', rawurlencode($token));
        $url = 'https://tapi.bale.ai/bot' . $safe_token . '/' . $method;
        $response = wp_remote_post($url, [
            'timeout' => 30,
            'headers' => ['Content-Type' => 'application/json; charset=utf-8'],
            'body' => wp_json_encode($payload, JSON_UNESCAPED_UNICODE),
        ]);

        if (is_wp_error($response)) {
            return $this->error('wmsm_bale_connection_failed', 'ارتباط با بله برقرار نشد: ' . $response->get_error_message(), 500);
        }

        $code = (int) wp_remote_retrieve_response_code($response);
        $body = (string) wp_remote_retrieve_body($response);
        $json = json_decode($body, true);

        if ($code < 200 || $code >= 300) {
            $description = is_array($json) && !empty($json['description']) ? $json['description'] : 'خطای نامشخص از سمت بله';
            return $this->error('wmsm_bale_api_error', 'ارسال به بله ناموفق بود: ' . sanitize_text_field($description), 500);
        }

        if (is_array($json) && array_key_exists('ok', $json) && !$json['ok']) {
            $description = !empty($json['description']) ? $json['description'] : 'درخواست بله رد شد.';
            return $this->error('wmsm_bale_api_not_ok', 'ارسال به بله ناموفق بود: ' . sanitize_text_field($description), 500);
        }

        return true;
    }

    private function build_bale_caption(WC_Product $product, string $manual_text = ''): string {
        $parts = [];
        $manual_text = trim($manual_text);
        if ($manual_text !== '') {
            $parts[] = $manual_text;
        }

        $parts[] = '📦 ' . $product->get_name();

        $attributes_text = $this->get_product_attributes_text($product);
        if ($attributes_text !== '') {
            $parts[] = "مشخصات:\n" . $attributes_text;
        }

        $regular_price = $product->get_regular_price();
        $price = $regular_price !== '' ? $regular_price : $product->get_price();
        if ($price !== '') {
            $parts[] = '💰 قیمت: ' . wc_price($price, ['currency' => get_woocommerce_currency()]);
        }

        return wp_strip_all_tags(implode("\n\n", $parts));
    }

    private function build_bale_order_button(WC_Product $product): array {
        $permalink = get_permalink($product->get_id());
        if (!$permalink) {
            return [];
        }

        return [
            'inline_keyboard' => [
                [
                    [
                        'text' => '🛒 سفارش محصول',
                        'url' => esc_url_raw($permalink),
                    ],
                ],
            ],
        ];
    }

    private function get_product_attributes_text(WC_Product $product): string {
        $lines = [];
        foreach ($product->get_attributes() as $attribute) {
            if (!$attribute instanceof WC_Product_Attribute || !$attribute->get_visible()) {
                continue;
            }

            $name = wc_attribute_label($attribute->get_name());
            if ($attribute->is_taxonomy()) {
                $values = wc_get_product_terms($product->get_id(), $attribute->get_name(), ['fields' => 'names']);
            } else {
                $values = $attribute->get_options();
            }

            $value = implode('، ', array_filter(array_map('strval', $values)));
            if ($name !== '' && $value !== '') {
                $lines[] = '• ' . $name . ': ' . $value;
            }
            if (count($lines) >= 8) {
                break;
            }
        }

        $sku = $product->get_sku();
        if ($sku !== '') {
            array_unshift($lines, '• کد محصول: ' . $sku);
        }

        return implode("\n", $lines);
    }

    private function ensure_bale_settings() {
        if ($this->get_bale_bot_token() === '') {
            return $this->error('wmsm_bale_token_missing', 'توکن بازوی بله تنظیم نشده است.', 400);
        }
        if ($this->get_bale_chat_id() === '') {
            return $this->error('wmsm_bale_chat_missing', 'شناسه یا نام کاربری کانال بله تنظیم نشده است.', 400);
        }
        return true;
    }

    private function get_product_ids_by_category(int $category_id): array {
        $query = new WP_Query([
            'post_type' => 'product',
            'post_status' => 'publish',
            'posts_per_page' => -1,
            'orderby' => 'date',
            'order' => 'DESC',
            'fields' => 'ids',
            'tax_query' => [[
                'taxonomy' => 'product_cat',
                'field' => 'term_id',
                'terms' => [$category_id],
            ]],
        ]);
        return array_map('absint', $query->posts);
    }

    private function get_bale_jobs(): array {
        $jobs = get_option(self::BALE_JOBS_OPTION, []);
        return is_array($jobs) ? $jobs : [];
    }

    private function format_bale_jobs(): array {
        $items = [];
        foreach ($this->get_bale_jobs() as $job) {
            $total = max(0, absint($job['total'] ?? 0));
            $index = max(0, absint($job['index'] ?? 0));
            $items[] = [
                'category_id' => absint($job['category_id'] ?? 0),
                'category_name' => (string) ($job['category_name'] ?? ''),
                'interval_minutes' => absint($job['interval_minutes'] ?? 0),
                'sent_count' => min($index, $total),
                'total' => $total,
                'next_run' => !empty($job['next_run']) ? gmdate('c', absint($job['next_run'])) : '',
                'status' => (string) ($job['status'] ?? 'active'),
            ];
        }
        return $items;
    }

    private function get_bale_bot_token(): string {
        return trim((string) get_option(self::BALE_BOT_TOKEN_OPTION, ''));
    }

    private function get_bale_chat_id(): string {
        return trim((string) get_option(self::BALE_CHAT_ID_OPTION, ''));
    }

    private function get_bale_cooldown_key(int $product_id): string {
        return 'wmsm_bale_cooldown_' . $product_id;
    }

    private function set_bale_cooldown(int $product_id): void {
        set_transient($this->get_bale_cooldown_key($product_id), time() + self::BALE_COOLDOWN_SECONDS, self::BALE_COOLDOWN_SECONDS);
    }

    private function get_bale_cooldown_remaining(int $product_id): int {
        $until = (int) get_transient($this->get_bale_cooldown_key($product_id));
        return max(0, $until - time());
    }

    private function format_seconds(int $seconds): string {
        $minutes = (int) ceil($seconds / 60);
        if ($minutes < 60) {
            return $minutes . ' دقیقه';
        }
        return 'حدود ' . ceil($minutes / 60) . ' ساعت';
    }

    private function limit_text(string $text, int $max): string {
        if (function_exists('mb_strlen') && mb_strlen($text, 'UTF-8') > $max) {
            return mb_substr($text, 0, $max - 3, 'UTF-8') . '...';
        }
        if (!function_exists('mb_strlen') && strlen($text) > $max) {
            return substr($text, 0, $max - 3) . '...';
        }
        return $text;
    }

    private function authenticate_token(WP_REST_Request $request) {
        $header = $this->get_authorization_header();
        if (!$header && $request->get_header('x_wmsm_token')) {
            $header = 'Bearer ' . $request->get_header('x_wmsm_token');
        }

        if (!$header || !preg_match('/Bearer\s+(.*)$/i', $header, $matches)) {
            return $this->error('wmsm_missing_token', 'توکن ورود ارسال نشده است.', 401);
        }

        $token = trim($matches[1]);
        $parts = explode(':', $token, 2);
        if (count($parts) !== 2) {
            return $this->error('wmsm_invalid_token', 'توکن ورود معتبر نیست.', 401);
        }

        $user_id = absint($parts[0]);
        $secret = $parts[1];
        if (!$user_id || $secret === '') {
            return $this->error('wmsm_invalid_token', 'توکن ورود معتبر نیست.', 401);
        }

        $hash = (string) get_user_meta($user_id, self::TOKEN_HASH_META, true);
        $expires = (int) get_user_meta($user_id, self::TOKEN_EXPIRES_META, true);

        if (!$hash || !$expires || $expires < time()) {
            return $this->error('wmsm_expired_token', 'نشست شما منقضی شده است. دوباره وارد شوید.', 401);
        }

        if (!wp_check_password($secret, $hash, $user_id)) {
            return $this->error('wmsm_invalid_token', 'توکن ورود معتبر نیست.', 401);
        }

        $user = get_user_by('id', $user_id);
        if (!$user) {
            return $this->error('wmsm_user_not_found', 'کاربر پیدا نشد.', 401);
        }

        return $user;
    }

    private function get_authorization_header(): string {
        if (!empty($_SERVER['HTTP_AUTHORIZATION'])) {
            return sanitize_text_field(wp_unslash($_SERVER['HTTP_AUTHORIZATION']));
        }

        if (!empty($_SERVER['REDIRECT_HTTP_AUTHORIZATION'])) {
            return sanitize_text_field(wp_unslash($_SERVER['REDIRECT_HTTP_AUTHORIZATION']));
        }

        if (function_exists('apache_request_headers')) {
            $headers = apache_request_headers();
            foreach ($headers as $key => $value) {
                if (strtolower($key) === 'authorization') {
                    return sanitize_text_field($value);
                }
            }
        }

        return '';
    }

    private function user_can_manage_products(WP_User $user): bool {
        return user_can($user, 'manage_woocommerce') || user_can($user, 'edit_products');
    }

    private function can_edit_this_product(int $product_id): bool {
        $user = $this->authorized_user ?: wp_get_current_user();
        if (!$user || !$user->ID) {
            return false;
        }

        return user_can($user, 'manage_woocommerce') || user_can($user, 'edit_post', $product_id) || user_can($user, 'edit_products');
    }

    private function ensure_woocommerce() {
        if (!class_exists('WooCommerce') || !function_exists('wc_get_product')) {
            return $this->error('wmsm_woocommerce_missing', 'ووکامرس نصب یا فعال نیست.', 500);
        }
        return true;
    }

    private function format_product(WC_Product $product): array {
        $last_action = (string) get_post_meta($product->get_id(), self::LAST_ACTION_META, true);
        $last_action_at = (string) get_post_meta($product->get_id(), self::LAST_ACTION_AT_META, true);
        $updated_action_at = (string) get_post_meta($product->get_id(), self::UPDATED_ACTION_AT_META, true);
        $bale_sent_action_at = (string) get_post_meta($product->get_id(), self::BALE_SENT_ACTION_AT_META, true);

        if (!$this->is_last_action_recent($last_action_at)) {
            $last_action = '';
            $last_action_at = '';
        }
        if (!$this->is_last_action_recent($updated_action_at)) {
            $updated_action_at = '';
        }
        if (!$this->is_last_action_recent($bale_sent_action_at)) {
            $bale_sent_action_at = '';
        }

        // وضعیت نهایی رنگ کارت در اپ. اگر هر دو اکشن در ۲۴ ساعت اخیر باشند، both می‌شود.
        $action_state = 'none';
        if ($updated_action_at !== '' && $bale_sent_action_at !== '') {
            $action_state = 'both';
        } elseif ($updated_action_at !== '') {
            $action_state = 'updated';
        } elseif ($bale_sent_action_at !== '') {
            $action_state = 'bale_sent';
        }

        return [
            'id' => (int) $product->get_id(),
            'name' => $product->get_name(),
            'price' => (string) $product->get_price(),
            'regular_price' => (string) $product->get_regular_price(),
            'stock_quantity' => $product->get_stock_quantity(),
            'stock_status' => $product->get_stock_status(),
            'image_url' => $this->get_product_image_url($product),
            'bale_cooldown_remaining' => $this->get_bale_cooldown_remaining($product->get_id()),
            'last_action' => $last_action,
            'last_action_at' => $last_action_at,
            'updated_action_at' => $updated_action_at,
            'bale_sent_action_at' => $bale_sent_action_at,
            'action_state' => $action_state,
        ];
    }

    private function is_last_action_recent(string $last_action_at): bool {
        if ($last_action_at === '') {
            return false;
        }

        $timestamp = strtotime($last_action_at);
        if (!$timestamp) {
            return false;
        }

        return $timestamp >= (time() - DAY_IN_SECONDS);
    }

    private function set_product_last_action(int $product_id, string $action): void {
        if (!in_array($action, ['updated', 'bale_sent'], true)) {
            return;
        }

        $now = gmdate('c');
        update_post_meta($product_id, self::LAST_ACTION_META, $action);
        update_post_meta($product_id, self::LAST_ACTION_AT_META, $now);

        // زمان هر اکشن جدا ذخیره می‌شود تا اگر محصول هم بروزرسانی شد و هم به بله رفت، در اپ گرادیانت سبز/آبی شود.
        if ($action === 'updated') {
            update_post_meta($product_id, self::UPDATED_ACTION_AT_META, $now);
        }
        if ($action === 'bale_sent') {
            update_post_meta($product_id, self::BALE_SENT_ACTION_AT_META, $now);
        }
    }

    private function get_product_image_url(WC_Product $product, string $size = 'woocommerce_thumbnail'): string {
        $image_id = $product->get_image_id();
        if (!$image_id) {
            return '';
        }
        $url = wp_get_attachment_image_url($image_id, $size);
        if (!$url && $size !== 'medium') {
            $url = wp_get_attachment_image_url($image_id, 'medium');
        }
        return $url ?: '';
    }

    private function create_random_secret(): string {
        try {
            return bin2hex(random_bytes(32));
        } catch (Exception $e) {
            return wp_generate_password(64, false, false);
        }
    }

    private function error(string $code, string $message, int $status): WP_Error {
        return new WP_Error($code, $message, ['status' => $status]);
    }
}

new WMSM_Woo_Mobile_Stock_Manager_API();

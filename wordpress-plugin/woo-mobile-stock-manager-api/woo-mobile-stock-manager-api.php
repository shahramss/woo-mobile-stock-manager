<?php
/**
 * Plugin Name: Woo Mobile Stock Manager API
 * Description: REST API امن برای اپلیکیشن موبایل مدیریت قیمت، موجودی، تصویر، دسته‌بندی و جستجوی محصولات ووکامرس.
 * Version: 1.1.0
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

    private $authorized_user = null;

    public function __construct() {
        add_action('rest_api_init', [$this, 'register_routes']);
        add_action('admin_notices', [$this, 'woocommerce_admin_notice']);
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
                'category_id' => [
                    'required' => false,
                    'type' => 'integer',
                    'sanitize_callback' => 'absint',
                ],
                'search' => [
                    'required' => false,
                    'type' => 'string',
                    'sanitize_callback' => 'sanitize_text_field',
                ],
                'page' => [
                    'required' => false,
                    'type' => 'integer',
                    'default' => 1,
                    'sanitize_callback' => 'absint',
                ],
                'per_page' => [
                    'required' => false,
                    'type' => 'integer',
                    'default' => 20,
                    'sanitize_callback' => 'absint',
                ],
            ],
        ]);

        register_rest_route(self::NAMESPACE, '/products/(?P<id>\d+)', [
            [
                'methods' => WP_REST_Server::READABLE,
                'callback' => [$this, 'get_product'],
                'permission_callback' => [$this, 'can_access'],
                'args' => [
                    'id' => [
                        'required' => true,
                        'type' => 'integer',
                        'sanitize_callback' => 'absint',
                    ],
                ],
            ],
            [
                'methods' => WP_REST_Server::EDITABLE,
                'callback' => [$this, 'update_product'],
                'permission_callback' => [$this, 'can_access'],
                'args' => [
                    'id' => [
                        'required' => true,
                        'type' => 'integer',
                        'sanitize_callback' => 'absint',
                    ],
                ],
            ],
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

        // احراز هویت با همان حساب وردپرس
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

        $token = $user->ID . ':' . $secret;

        return rest_ensure_response([
            'token' => $token,
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

        $args = [
            'post_type' => 'product',
            'post_status' => ['publish', 'private', 'draft', 'pending'],
            'posts_per_page' => $per_page,
            'paged' => $page,
            'orderby' => 'title',
            'order' => 'ASC',
            'fields' => 'ids',
        ];

        if ($search !== '') {
            // جستجو داخل عنوان/متن محصول؛ اگر دسته هم ارسال شود، فقط در همان دسته جستجو می‌شود.
            $args['s'] = $search;
        }

        if ($category_id > 0) {
            $args['tax_query'] = [
                [
                    'taxonomy' => 'product_cat',
                    'field' => 'term_id',
                    'terms' => [$category_id],
                ],
            ];
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
            if (!is_numeric($stock_quantity) || (int) $stock_quantity < 0) {
                return $this->error('wmsm_invalid_stock_quantity', 'تعداد موجودی معتبر نیست.', 400);
            }
            // برای اینکه عدد موجودی واقعاً ذخیره شود، مدیریت موجودی فعال می‌شود.
            $product->set_manage_stock(true);
            $product->set_stock_quantity(wc_stock_amount($stock_quantity));
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
        } catch (Exception $e) {
            return $this->error('wmsm_save_failed', 'ذخیره محصول انجام نشد.', 500);
        }

        return rest_ensure_response($this->format_product($product));
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
        $image_url = '';
        $image_id = $product->get_image_id();
        if ($image_id) {
            $image_url = wp_get_attachment_image_url($image_id, 'woocommerce_thumbnail');
            if (!$image_url) {
                $image_url = wp_get_attachment_image_url($image_id, 'medium');
            }
        }

        return [
            'id' => (int) $product->get_id(),
            'name' => $product->get_name(),
            'price' => (string) $product->get_price(),
            'regular_price' => (string) $product->get_regular_price(),
            'stock_quantity' => $product->get_stock_quantity(),
            'stock_status' => $product->get_stock_status(),
            'image_url' => $image_url ?: '',
        ];
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

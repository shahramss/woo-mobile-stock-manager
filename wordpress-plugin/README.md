# افزونه Woo Mobile Stock Manager API

این افزونه API امن برای اپ مدیریت بانومی می‌سازد.

Endpoints:

- POST `/wp-json/wmsm/v1/login`
- GET `/wp-json/wmsm/v1/categories`
- GET `/wp-json/wmsm/v1/products?category_id=12&search=قفل&page=1&per_page=20`
- GET `/wp-json/wmsm/v1/products/{id}`
- PUT `/wp-json/wmsm/v1/products/{id}`

خروجی محصول شامل `image_url` هم هست تا تصویر محصول در اپ نمایش داده شود.

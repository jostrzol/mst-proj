/* WiFi station Example

   This example code is in the Public Domain (or CC0 licensed, at your option.)

   Unless required by applicable law or agreed to in writing, this
   software is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
   CONDITIONS OF ANY KIND, either express or implied.
*/
#include <string.h>

#include "esp_err.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_wifi.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"

#include "wifi.h"

#define ESP_WIFI_SSID CONFIG_ESP_WIFI_SSID
#define ESP_WIFI_PASS CONFIG_ESP_WIFI_PASSWORD
#define ESP_MAXIMUM_RETRY CONFIG_ESP_MAXIMUM_RETRY

/* The event group allows multiple bits for each event, but we only care about
 * two events:
 * - we are connected to the AP with an IP
 * - we failed to connect after the maximum amount of retries */
#define WIFI_CONNECTED_BIT BIT0
#define WIFI_FAIL_BIT BIT1

static const char *TAG = "wifi";

/* FreeRTOS event group to signal when we are connected*/
static EventGroupHandle_t s_wifi_event_group;
static int s_retry_num = 0;

static void event_handler(
    void *arg, esp_event_base_t event_base, int32_t event_id, void *event_data
) {
  if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START) {
    esp_wifi_connect();
  } else if (event_base == WIFI_EVENT &&
             event_id == WIFI_EVENT_STA_DISCONNECTED) {
    if (s_retry_num < ESP_MAXIMUM_RETRY) {
      esp_wifi_connect();
      s_retry_num++;
      ESP_LOGI(TAG, "retry to connect to the AP");
    } else {
      xEventGroupSetBits(s_wifi_event_group, WIFI_FAIL_BIT);
    }
    ESP_LOGI(TAG, "connect to the AP fail");
  } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
    ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;
    ESP_LOGI(TAG, "got ip:" IPSTR, IP2STR(&event->ip_info.ip));
    s_retry_num = 0;
    xEventGroupSetBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
  }
}

esp_err_t my_wifi_init(my_wifi_t *self) {
  esp_err_t err;

  // Init
  if (s_wifi_event_group != NULL) {
    ESP_LOGE(TAG, "Wifi already set up");
    return ESP_ERR_INVALID_STATE;
  }
  s_wifi_event_group = xEventGroupCreate();
  if (s_wifi_event_group == NULL) {
    ESP_LOGE(TAG, "xEventGroupCreate fail");
    return ESP_ERR_INVALID_STATE;
  }

  err = esp_netif_init();
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "esp_netif_init fail (0x%x)", (int)err);
    return err;
  }

  esp_netif_t *netif = esp_netif_create_default_wifi_sta();
  if (netif == NULL) {
    ESP_LOGE(TAG, "esp_netif_create_default_wifi_sta fail (0x%x)", (int)err);
    ESP_ERROR_CHECK_WITHOUT_ABORT(esp_netif_deinit());
    return ESP_ERR_INVALID_STATE;
  }

  wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
  err = esp_wifi_init(&cfg);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "esp_wifi_init fail (0x%x)", (int)err);
    esp_netif_destroy_default_wifi(netif);
    ESP_ERROR_CHECK_WITHOUT_ABORT(esp_netif_deinit());
    return err;
  }

  // Handlers
  esp_event_handler_instance_t handler_wifi;
  err = esp_event_handler_instance_register(
      WIFI_EVENT, ESP_EVENT_ANY_ID, &event_handler, NULL, &handler_wifi
  );
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "esp_event_handler_instance_register fail (0x%x)", (int)err);
    esp_netif_destroy_default_wifi(netif);
    ESP_ERROR_CHECK_WITHOUT_ABORT(esp_netif_deinit());
    return err;
  }

  esp_event_handler_instance_t handler_ip;
  err = esp_event_handler_instance_register(
      IP_EVENT, IP_EVENT_STA_GOT_IP, &event_handler, NULL, &handler_ip
  );
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "esp_event_handler_instance_register fail (0x%x)", (int)err);
    esp_netif_destroy_default_wifi(netif);
    ESP_ERROR_CHECK_WITHOUT_ABORT(esp_netif_deinit());
    return err;
  }

  // Config
  err = esp_wifi_set_mode(WIFI_MODE_STA);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "esp_wifi_set_mode fail (0x%x)", (int)err);
    esp_netif_destroy_default_wifi(netif);
    ESP_ERROR_CHECK_WITHOUT_ABORT(esp_netif_deinit());
    return err;
  }
  wifi_config_t wifi_config = {
      .sta =
          {
              .ssid = ESP_WIFI_SSID,
              .password = ESP_WIFI_PASS,
              .threshold.authmode = WIFI_AUTH_WPA2_PSK,
              .sae_pwe_h2e = WPA3_SAE_PWE_UNSPECIFIED,
              .sae_h2e_identifier = "",
          },
  };
  err = esp_wifi_set_config(WIFI_IF_STA, &wifi_config);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "esp_wifi_set_config fail (0x%x)", (int)err);
    esp_netif_destroy_default_wifi(netif);
    ESP_ERROR_CHECK_WITHOUT_ABORT(esp_netif_deinit());
    return err;
  }
  err = esp_wifi_start();
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "esp_wifi_start fail (0x%x)", (int)err);
    esp_netif_destroy_default_wifi(netif);
    ESP_ERROR_CHECK_WITHOUT_ABORT(esp_netif_deinit());
    return err;
  }

  /* Waiting until either the connection is established (WIFI_CONNECTED_BIT) or
   * connection failed for the maximum number of re-tries (WIFI_FAIL_BIT). The
   * bits are set by event_handler() (see above) */
  EventBits_t bits = xEventGroupWaitBits(
      s_wifi_event_group, WIFI_CONNECTED_BIT | WIFI_FAIL_BIT, pdFALSE, pdFALSE,
      portMAX_DELAY
  );

  /* xEventGroupWaitBits() returns the bits before the call returned, hence we
   * can test which event actually happened. */
  if (bits & WIFI_CONNECTED_BIT) {
    ESP_LOGI(TAG, "connected to ap SSID:%s", ESP_WIFI_SSID);
  } else if (bits & WIFI_FAIL_BIT) {
    ESP_LOGI(TAG, "Failed to connect to SSID:%s", ESP_WIFI_SSID);
  } else {
    ESP_LOGE(TAG, "UNEXPECTED EVENT");
  }

  err = esp_wifi_set_ps(WIFI_PS_NONE);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "esp_wifi_start fail (0x%x)", (int)err);
    esp_netif_destroy_default_wifi(netif);
    ESP_ERROR_CHECK_WITHOUT_ABORT(esp_netif_deinit());
    return err;
  }

  *self = (my_wifi_t){.netif = netif};

  return ESP_OK;
}

void my_wifi_deinit(my_wifi_t *self) {
  esp_netif_destroy_default_wifi(self->netif);
  ESP_ERROR_CHECK_WITHOUT_ABORT(esp_netif_deinit());
}
